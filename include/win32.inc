; win32 imports + only the constants actually used.
; one-off api in a single file? extern it there, dup externs are fine
%ifndef WIN32_INC
%define WIN32_INC

extern ExitProcess, GetModuleHandleA, GetCommandLineA, GetLastError
extern QueryPerformanceCounter, QueryPerformanceFrequency, Sleep, GetTickCount64
extern GetProcessHeap, HeapAlloc, HeapFree, HeapReAlloc
extern VirtualAlloc, VirtualFree
extern CreateFileA, ReadFile, WriteFile, CloseHandle, GetFileSizeEx, SetFilePointerEx
extern CreateDirectoryA, DeleteFileA, FindFirstFileA, FindNextFileA, FindClose
extern GetFileAttributesA, MoveFileExA
extern CreateThread, WaitForSingleObject, WaitForMultipleObjects, CreateEventA, SetEvent, ResetEvent
extern InitializeCriticalSection, EnterCriticalSection, LeaveCriticalSection, DeleteCriticalSection
extern GetSystemInfo, OutputDebugStringA, GetStdHandle, AttachConsole, GetLocalTime
extern SetThreadPriority, GetCurrentThread
extern RegisterClassExA, CreateWindowExA, DestroyWindow, DefWindowProcA, ShowWindow, UpdateWindow
extern PeekMessageA, TranslateMessage, DispatchMessageA, PostQuitMessage
extern LoadCursorA, LoadIconA, SetCursor, ShowCursor, SetCursorPos, GetCursorPos, ClientToScreen, ScreenToClient
extern ClipCursor, GetClientRect, GetWindowRect, AdjustWindowRect, SetWindowPos, SetWindowLongPtrA, GetWindowLongPtrA
extern MessageBoxA, GetDC, ReleaseDC, RegisterRawInputDevices, GetRawInputData, SetWindowTextA
extern GetSystemMetrics, MonitorFromWindow, GetMonitorInfoA, GetForegroundWindow, SetForegroundWindow
extern GetAsyncKeyState, OpenClipboard, CloseClipboard, GetClipboardData
extern ChoosePixelFormat, SetPixelFormat, SwapBuffers, DescribePixelFormat
extern waveOutOpen, waveOutClose, waveOutPrepareHeader, waveOutUnprepareHeader, waveOutWrite, waveOutReset
extern timeBeginPeriod, timeEndPeriod

%define NULL                   0
%define TRUE                    1
%define FALSE                   0
%define INVALID_HANDLE_VALUE    -1
%define INFINITE                0xFFFFFFFF

%define MEM_COMMIT              0x1000
%define MEM_RESERVE             0x2000
%define MEM_RELEASE             0x8000
%define PAGE_READWRITE          0x04
%define HEAP_ZERO_MEMORY        0x08

%define GENERIC_READ            0x80000000
%define GENERIC_WRITE           0x40000000
%define FILE_SHARE_READ         1
%define CREATE_ALWAYS           2
%define OPEN_EXISTING           3
%define FILE_ATTRIBUTE_NORMAL   0x80
%define FILE_ATTRIBUTE_DIRECTORY 0x10
%define INVALID_FILE_ATTRIBUTES 0xFFFFFFFF
%define MOVEFILE_REPLACE_EXISTING 1

%define CS_VREDRAW              1
%define CS_HREDRAW              2
%define CS_OWNDC                0x20
%define WS_OVERLAPPEDWINDOW     0x00CF0000
%define WS_POPUP                0x80000000
%define WS_VISIBLE              0x10000000
%define WS_CLIPSIBLINGS         0x04000000
%define WS_CLIPCHILDREN         0x02000000
%define CW_USEDEFAULT           0x80000000
%define SW_SHOW                 5
%define GWL_STYLE               -16
%define HWND_TOP                0
%define SWP_FRAMECHANGED        0x20
%define SWP_NOZORDER            0x04
%define SWP_SHOWWINDOW          0x40
%define PM_REMOVE               1
%define IDC_ARROW               32512
%define IDI_APPLICATION         32512
%define MB_OK                   0
%define MB_ICONERROR            0x10
%define SM_CXSCREEN             0
%define SM_CYSCREEN             1

%define WM_CREATE               0x0001
%define WM_DESTROY              0x0002
%define WM_SIZE                 0x0005
%define WM_ACTIVATE             0x0006
%define WM_SETFOCUS             0x0007
%define WM_KILLFOCUS            0x0008
%define WM_CLOSE                0x0010
%define WM_QUIT                 0x0012
%define WM_SETCURSOR            0x0020
%define WM_INPUT                0x00FF
%define WM_KEYDOWN              0x0100
%define WM_KEYUP                0x0101
%define WM_CHAR                 0x0102
%define WM_SYSKEYDOWN           0x0104
%define WM_SYSKEYUP             0x0105
%define WM_MOUSEMOVE            0x0200
%define WM_LBUTTONDOWN          0x0201
%define WM_LBUTTONUP            0x0202
%define WM_RBUTTONDOWN          0x0204
%define WM_RBUTTONUP            0x0205
%define WM_MBUTTONDOWN          0x0207
%define WM_MBUTTONUP            0x0208
%define WM_MOUSEWHEEL           0x020A

%define PFD_DRAW_TO_WINDOW      0x04
%define PFD_SUPPORT_OPENGL      0x20
%define PFD_DOUBLEBUFFER        0x01
%define PFD_TYPE_RGBA           0
%define PFD_MAIN_PLANE          0

%define RID_INPUT               0x10000003
%define RIM_TYPEMOUSE           0

%define WAVE_MAPPER             -1
%define WAVE_FORMAT_PCM         1
%define CALLBACK_EVENT          0x00050000
%define WHDR_DONE               1

%define VK_LBUTTON  0x01
%define VK_BACK     0x08
%define VK_TAB      0x09
%define VK_RETURN   0x0D
%define VK_SHIFT    0x10
%define VK_CONTROL  0x11
%define VK_MENU     0x12
%define VK_ESCAPE   0x1B
%define VK_SPACE    0x20
%define VK_PRIOR    0x21
%define VK_NEXT     0x22
%define VK_END      0x23
%define VK_HOME     0x24
%define VK_LEFT     0x25
%define VK_UP       0x26
%define VK_RIGHT    0x27
%define VK_DOWN     0x28
%define VK_DELETE   0x2E
%define VK_F1       0x70
%define VK_F2       0x71
%define VK_F3       0x72
%define VK_F4       0x73
%define VK_F5       0x74
%define VK_F6       0x75
%define VK_F7       0x76
%define VK_F8       0x77
%define VK_F11      0x7A
%define VK_LSHIFT   0xA0
%define VK_LCONTROL 0xA2
%define VK_OEM_2    0xBF            ; /
%define VK_OEM_3    0xC0            ; backtick
; letters/digits = uppercase ascii

; platform.asm only
%define SIZEOF_WNDCLASSEX       80
%define SIZEOF_PFD              40
%define SIZEOF_MSG              48

%endif
