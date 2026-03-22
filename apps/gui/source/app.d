import downloader;
import downloader.profiles;
import core.sys.windows.windows;
import core.sys.windows.windef : MAX_PATH;
import std.utf : toUTF8;
import std.string : fromStringz, toStringz;
import std.algorithm : countUntil, sort;
import std.format : format;
import std.concurrency : spawn;

// Win32 externs for window enumeration
extern(Windows) nothrow {
    alias WNDENUMPROC = BOOL function(HWND, LPARAM);
    BOOL EnumWindows(WNDENUMPROC lpEnumFunc, LPARAM lParam);
    int GetWindowTextW(HWND hWnd, LPWSTR lpString, int nMaxCount);
    BOOL IsWindowVisible(HWND hWnd);
    DWORD GetCurrentProcessId();
    DWORD GetWindowThreadProcessId(HWND hWnd, LPDWORD lpdwProcessId);
    HANDLE OpenProcess(DWORD dwDesiredAccess, BOOL bInheritHandle, DWORD dwProcessId);
    BOOL QueryFullProcessImageNameW(HANDLE hProcess, DWORD dwFlags, LPWSTR lpExeName, PDWORD lpdwSize);
    BOOL CloseHandle(HANDLE hObject);
}

const DWORD PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

struct WindowInfo {
    string title;
    string exeName; // To help match browser
    HWND hwnd;
}

extern(Windows) nothrow BOOL enumWindowsProc(HWND hwnd, LPARAM lParam) {
    try {
        if (!IsWindowVisible(hwnd)) return TRUE;
        
        DWORD pid;
        GetWindowThreadProcessId(hwnd, &pid);
        if (pid == GetCurrentProcessId()) return TRUE; // Exclude self

        wchar[MAX_PATH] exePath;
        DWORD exePathSize = cast(DWORD)exePath.length;
        string exeBaseName = "";
        
        HANDLE hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
        if (hProcess) {
            if (QueryFullProcessImageNameW(hProcess, 0, exePath.ptr, &exePathSize)) {
                import std.path : baseName;
                exeBaseName = toUTF8(exePath[0..exePathSize]);
                exeBaseName = baseName(exeBaseName);
            }
            CloseHandle(hProcess);
        }

        if (exeBaseName == "") return TRUE;

        // Check if it's one of the known browsers by process name
        import std.string : toLower;
        string lowExe = exeBaseName.toLower();
        bool isBrowser = false;
        string browserMatch = "";

        if (lowExe == "chrome.exe") { isBrowser = true; browserMatch = "Chrome"; }
        else if (lowExe == "msedge.exe") { isBrowser = true; browserMatch = "Edge"; }
        else if (lowExe == "brave.exe") { isBrowser = true; browserMatch = "Brave"; }
        else if (lowExe == "vivaldi.exe") { isBrowser = true; browserMatch = "Vivaldi"; }
        else if (lowExe == "opera.exe") { isBrowser = true; browserMatch = "Opera"; }


        if (isBrowser) {
            wchar[512] title;
            int len = GetWindowTextW(hwnd, title.ptr, cast(int)title.length);
            string t = "";
            if (len > 0) { t = toUTF8(title[0..len]); }
            
            auto list = cast(WindowInfo[]*)lParam;
            (*list) ~= WindowInfo(t, browserMatch, hwnd);
        }
    } catch (Exception) {
        // Callback must not throw
    }
    return TRUE;
}

WindowInfo[] getZOrderedBrowsers() {
    WindowInfo[] list;
    EnumWindows(&enumWindowsProc, cast(LPARAM)&list);
    return list;
}

import ggwebview.webview;
import std.stdio;
import std.json;

void main() {
    auto wv = new WebView(true, null);
    wv.setTitle("Site Downloader");
    wv.setSize(1200, 800, webview_hint_t.WEBVIEW_HINT_NONE);

    wv.bind("getProfiles", (string seq, string req, WebView wv) {
        try {
            auto activeWindows = getZOrderedBrowsers();
            auto allProfiles = findChromiumProfiles();
            
            JSONValue[] activeArr;
            JSONValue[] inactiveArr;
            
            foreach(p; allProfiles) {
                bool isActive = false;
                foreach(win; activeWindows) {
                    import std.string : indexOf, toLower;
                    import std.path : baseName;
                    
                    string title = win.title.toLower();
                    string winBrowser = win.exeName.toLower();
                    
                    if (winBrowser != p.browser.toLower()) continue;

                    string pName = p.name.toLower();
                    string dirName = p.path.baseName().toLower();

                    // Heuristic: Display name match OR Default folder match if win title is generic
                    if (title.indexOf(pName) != -1 || 
                        (dirName == "default" && (title.indexOf("personal") != -1 || 
                         title.indexOf("person 1") != -1))) {
                        isActive = true;
                        break;
                    }
                }

                auto j = JSONValue([
                    "name": JSONValue(p.name),
                    "browser": JSONValue(p.browser),
                    "path": JSONValue(p.path)
                ]);
                j.object["active"] = JSONValue(isActive);
                
                if (isActive) activeArr ~= j;
                else inactiveArr ~= j;
            }
            
            wv.webviewReturn(seq, true, JSONValue(activeArr ~ inactiveArr).toString());
        } catch (Exception e) {
            wv.webviewReturn(seq, false, `{"status": "error", "message": "` ~ e.msg ~ `"}`);
        }
    });

    wv.bind("getAbsolutePath", (string seq, string req, WebView wv) {
        try {
            import std.path : absolutePath;
            auto j = parseJSON(req);
            string path = (j.type == JSONType.array && j.array.length > 0) ? j[0].str : "";
            wv.webviewReturn(seq, true, JSONValue(absolutePath(path)).toString());
        } catch (Exception e) {
            wv.webviewReturn(seq, false, `{"status": "error", "message": "` ~ e.msg ~ `"}`);
        }
    });

    wv.bind("selectDirectory", (string seq, string req, WebView wv) {
        try {
            import std.process : executeShell;
            import std.string : strip;
            
            string cmd = "Add-Type -AssemblyName System.Windows.Forms; " ~
                         "$f = New-Object System.Windows.Forms.FolderBrowserDialog; " ~
                         "$f.Description = 'Select Output Directory'; " ~
                         "if($f.ShowDialog() -eq 'OK') { $f.SelectedPath }";
                         
            auto res = executeShell("powershell -c \"" ~ cmd ~ "\"");
            wv.webviewReturn(seq, true, JSONValue(res.output.strip()).toString());
        } catch (Exception e) {
            wv.webviewReturn(seq, false, `{"status": "error", "message": "` ~ e.msg ~ `"}`);
        }
    });

    wv.bind("startArchive", (string seq, string req, WebView wv) {
        try {
            auto j = parseJSON(req);
            if (j.type != JSONType.array || j.array.length < 4) {
                throw new Exception("Invalid arguments. Expected 4: url, output, depth, profilePath");
            }
            string url = j[0].str;
            string output = j[1].str;
            int depth = cast(int)j[2].integer;
            string profilePath = j[3].str;

            import core.thread : Thread;
            import std.string : replace;
            
            // Capture for closure
            string url_c = url;
            string output_c = output;
            int depth_c = depth;
            string profilePath_c = profilePath;
            WebView wv_c = wv;

            auto t = new Thread({
                try {
                    auto sa = new SiteDownloader(url_c, output_c, false, "", false, "", profilePath_c);
                    sa.logCallback = (string s) {
                        import std.json : JSONValue;
                        string jsonEncodedMsg = JSONValue(s).toString();
                        wv_c.dispatch(() {
                            wv_c.evalScript("addLog(" ~ jsonEncodedMsg ~ ")");
                        });
                    };
                    sa.download(depth_c);
                    wv_c.dispatch(() {
                        wv_c.evalScript("addLog('SUCCESS: Process complete.')");
                    });
                } catch (Exception e) {
                    import std.json : JSONValue;
                    string jsonEncodedMsg = JSONValue("ERROR: " ~ e.msg).toString();
                    wv_c.dispatch(() {
                        wv_c.evalScript("addLog(" ~ jsonEncodedMsg ~ ")");
                    });
                }
            });
            t.isDaemon = true;
            t.start();

            wv.webviewReturn(seq, true, `{"status": "ok"}`);
        } catch (Exception e) {
            wv.webviewReturn(seq, false, `{"status": "error", "message": "` ~ e.msg ~ `"}`);
        }
    });

    wv.bind("saveSettings", (string seq, string req, WebView wv) {
        try {
            import std.file : write;
            auto j = parseJSON(req);
            string url = j[0].str;
            string path = j[1].str;
            write("settings.json", JSONValue(["url": JSONValue(url), "path": JSONValue(path)]).toString());
            wv.webviewReturn(seq, true, `{"status": "ok"}`);
        } catch (Exception e) {
            wv.webviewReturn(seq, false, `{"status": "error", "message": "` ~ e.msg ~ `"}`);
        }
    });

    wv.bind("loadSettings", (string seq, string req, WebView wv) {
        try {
            import std.file : readText, exists;
            if (exists("settings.json")) {
                wv.webviewReturn(seq, true, readText("settings.json"));
            } else {
                wv.webviewReturn(seq, true, `{"url": "", "path": "./archives"}`);
            }
        } catch (Exception e) {
            wv.webviewReturn(seq, false, `{"status": "error", "message": "` ~ e.msg ~ `"}`);
        }
    });

    string html = import("ui.html");
    wv.setHtml(html);
    wv.run();
}
