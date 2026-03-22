import core.sys.windows.windows;
import core.sys.windows.windef : MAX_PATH;
import std.stdio;
import std.utf;
import std.path;
import std.string;

const DWORD PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

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

extern(Windows) nothrow BOOL enumWindowsProc(HWND hwnd, LPARAM lParam) {
    try {
        if (!IsWindowVisible(hwnd)) return TRUE;
        
        DWORD pid;
        GetWindowThreadProcessId(hwnd, &pid);
        
        wchar[MAX_PATH] exePath;
        DWORD exePathSize = cast(DWORD)exePath.length;
        string exeBaseName = "";
        
        HANDLE hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
        if (hProcess) {
            if (QueryFullProcessImageNameW(hProcess, 0, exePath.ptr, &exePathSize)) {
                exeBaseName = toUTF8(exePath[0..exePathSize]);
                exeBaseName = baseName(exeBaseName);
            }
            CloseHandle(hProcess);
        }

        wchar[512] title;
        int len = GetWindowTextW(hwnd, title.ptr, cast(int)title.length);
        if (len > 0) {
            string t = toUTF8(title[0..len]);
            string lowExe = exeBaseName.toLower();
            if (lowExe == "chrome.exe" || lowExe == "msedge.exe") {
                try { writeln(lowExe, ": ", t); } catch (Exception) {}
            }
        }
    } catch(Exception) {}
    return TRUE;
}

void main() {
    EnumWindows(&enumWindowsProc, 0);
}
