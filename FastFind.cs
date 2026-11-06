// Fast multi-threaded file name search engine for the `search` command.
// Uses FindFirstFileExW with FindExInfoBasic + FIND_FIRST_EX_LARGE_FETCH, which is
// considerably faster than Get-ChildItem or Explorer search (no shell, no indexer).
// Written for C# 5 so Windows PowerShell 5.1's Add-Type can compile it.
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;

namespace WinSearch
{
    public sealed class Hit
    {
        public string Name { get; set; }
        public string Folder { get; set; }
        public string FullName { get; set; }
        public bool IsFolder { get; set; }
        public long Size { get; set; }
        public DateTime Modified { get; set; }
    }

    public sealed class Finder
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WIN32_FIND_DATA
        {
            public uint dwFileAttributes;
            public uint ftCreationLow, ftCreationHigh;
            public uint ftAccessLow, ftAccessHigh;
            public uint ftWriteLow, ftWriteHigh;
            public uint nFileSizeHigh, nFileSizeLow;
            public uint dwReserved0, dwReserved1;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string cFileName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] public string cAlternateFileName;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr FindFirstFileExW(string lpFileName, int fInfoLevelId,
            out WIN32_FIND_DATA lpFindFileData, int fSearchOp, IntPtr lpSearchFilter, int dwAdditionalFlags);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool FindNextFileW(IntPtr hFindFile, out WIN32_FIND_DATA lpFindFileData);

        [DllImport("kernel32.dll")]
        private static extern bool FindClose(IntPtr hFindFile);

        private const int FindExInfoBasic = 1;
        private const int FIND_FIRST_EX_LARGE_FETCH = 2;
        private const int ERROR_ACCESS_DENIED = 5;
        private const uint ATTR_DIRECTORY = 0x10;
        private const uint ATTR_REPARSE = 0x400;
        private const uint TAG_MOUNT_POINT = 0xA0000003; // junctions
        private const uint TAG_SYMLINK = 0xA000000C;
        private static readonly IntPtr INVALID_HANDLE = new IntPtr(-1);

        private readonly string[] roots;
        private readonly string needle;
        private readonly Regex regex;
        private readonly bool wantFiles, wantDirs;
        private readonly int limit;
        private readonly HashSet<string> exclude;
        private readonly int threadCount;

        private readonly ConcurrentStack<string> work = new ConcurrentStack<string>();
        private readonly SemaphoreSlim signal = new SemaphoreSlim(0);
        private readonly ConcurrentQueue<Hit> results = new ConcurrentQueue<Hit>();
        private int pending, found, dirsScanned, dirsDenied, running;
        private volatile bool stop;
        private volatile bool limitReached;

        public Finder(string[] roots, string pattern, bool files, bool dirs, int limit, string[] exclude, int threads)
        {
            this.roots = roots ?? new string[0];
            if (pattern.IndexOfAny(new[] { '*', '?' }) >= 0)
            {
                string rx = "^" + Regex.Escape(pattern).Replace(@"\*", ".*").Replace(@"\?", ".") + "$";
                regex = new Regex(rx, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
            }
            else
            {
                needle = pattern;
            }
            wantFiles = files;
            wantDirs = dirs;
            this.limit = limit;
            this.exclude = new HashSet<string>(exclude ?? new string[0], StringComparer.OrdinalIgnoreCase);
            threadCount = threads > 0 ? threads : Math.Max(4, Math.Min(Environment.ProcessorCount, 16));
        }

        public int DirsScanned { get { return Volatile.Read(ref dirsScanned); } }
        public int DirsDenied { get { return Volatile.Read(ref dirsDenied); } }
        public bool LimitReached { get { return limitReached; } }
        public bool IsDone { get { return Volatile.Read(ref running) == 0; } }

        public void Start()
        {
            if (roots.Length == 0) return;
            foreach (string r in roots)
            {
                Interlocked.Increment(ref pending);
                work.Push(r);
                signal.Release();
            }
            running = threadCount;
            for (int i = 0; i < threadCount; i++)
            {
                var t = new Thread(Worker);
                t.IsBackground = true;
                t.Start();
            }
        }

        public void Cancel()
        {
            if (stop) return;
            stop = true;
            signal.Release(threadCount);
        }

        public bool TryTake(out Hit hit)
        {
            return results.TryDequeue(out hit);
        }

        public static void Sort(List<Hit> hits)
        {
            hits.Sort(delegate (Hit a, Hit b)
            {
                int c = string.Compare(a.Folder, b.Folder, StringComparison.OrdinalIgnoreCase);
                return c != 0 ? c : string.Compare(a.Name, b.Name, StringComparison.OrdinalIgnoreCase);
            });
        }

        private void Worker()
        {
            try
            {
                while (true)
                {
                    signal.Wait();
                    if (stop) break;
                    string dir;
                    if (!work.TryPop(out dir)) continue;
                    try { Scan(dir); }
                    catch { /* never let one folder kill the search */ }
                    if (Interlocked.Decrement(ref pending) == 0) Cancel();
                }
            }
            finally
            {
                Interlocked.Decrement(ref running);
            }
        }

        private bool Match(string name)
        {
            return needle != null
                ? name.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0
                : regex.IsMatch(name);
        }

        private static string ToLongPath(string dir)
        {
            if (dir.StartsWith(@"\\?\")) return dir;
            if (dir.StartsWith(@"\\")) return @"\\?\UNC\" + dir.Substring(2);
            return @"\\?\" + dir;
        }

        private void Scan(string dir)
        {
            string baseDir = dir.TrimEnd('\\');
            WIN32_FIND_DATA fd;
            IntPtr h = FindFirstFileExW(ToLongPath(baseDir) + @"\*", FindExInfoBasic, out fd, 0, IntPtr.Zero, FIND_FIRST_EX_LARGE_FETCH);
            if (h == INVALID_HANDLE)
            {
                if (Marshal.GetLastWin32Error() == ERROR_ACCESS_DENIED) Interlocked.Increment(ref dirsDenied);
                return;
            }
            Interlocked.Increment(ref dirsScanned);
            try
            {
                do
                {
                    if (stop) return;
                    string name = fd.cFileName;
                    if (name == "." || name == "..") continue;

                    bool isDir = (fd.dwFileAttributes & ATTR_DIRECTORY) != 0;
                    string full = baseDir + "\\" + name;

                    if (isDir)
                    {
                        if (wantDirs && Match(name)) Add(fd, name, dir, full, true);
                        bool isLink = (fd.dwFileAttributes & ATTR_REPARSE) != 0
                                      && (fd.dwReserved0 == TAG_MOUNT_POINT || fd.dwReserved0 == TAG_SYMLINK);
                        if (!isLink && !exclude.Contains(name))
                        {
                            Interlocked.Increment(ref pending);
                            work.Push(full);
                            signal.Release();
                        }
                    }
                    else if (wantFiles && Match(name))
                    {
                        Add(fd, name, dir, full, false);
                    }
                } while (FindNextFileW(h, out fd));
            }
            finally
            {
                FindClose(h);
            }
        }

        private void Add(WIN32_FIND_DATA fd, string name, string folder, string full, bool isDir)
        {
            int n = Interlocked.Increment(ref found);
            if (limit > 0 && n > limit)
            {
                limitReached = true;
                Cancel();
                return;
            }
            long ft = ((long)fd.ftWriteHigh << 32) | fd.ftWriteLow;
            DateTime modified;
            try { modified = DateTime.FromFileTime(ft); } catch { modified = DateTime.MinValue; }
            results.Enqueue(new Hit
            {
                Name = name,
                Folder = folder,
                FullName = full,
                IsFolder = isDir,
                Size = isDir ? -1 : (((long)fd.nFileSizeHigh << 32) | fd.nFileSizeLow),
                Modified = modified
            });
        }
    }
}
