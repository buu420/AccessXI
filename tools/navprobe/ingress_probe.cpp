// Offline component audit using the same 32-bit DLL shipped by AccessXI.
// Connectivity only: runtime still repairs and validates every walking leg.
#include <windows.h>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <string>
#include <vector>
#include <map>
#include <cctype>
struct Position { float X, Y, Z; };
typedef void* (__cdecl *CreateFn)();
typedef void (__cdecl *DisposeFn)(void*);
typedef bool (__cdecl *LoadFn)(void*, const wchar_t*);
typedef bool (__cdecl *ValidFn)(void*, Position, bool);
typedef void (__cdecl *PathFn)(void*, Position, Position, bool);
typedef int (__cdecl *PointsFn)(void*, Position**);
static std::string key(const std::string& s) {
    std::string out;
    for (unsigned char c : s) if (isalnum(c)) out += (char)tolower(c);
    return out;
}
static std::vector<std::string> split(const std::string& s) {
    std::vector<std::string> out; size_t start = 0, end;
    while ((end = s.find('\t', start)) != std::string::npos) {
        out.push_back(s.substr(start, end - start)); start = end + 1;
    }
    out.push_back(s.substr(start)); return out;
}
static double distance(Position a, Position b) {
    return sqrt(pow(a.X-b.X, 2) + pow(a.Y-b.Y, 2) + pow(a.Z-b.Z, 2));
}
int main(int argc, char** argv) {
    if (argc != 5) { puts("ingress_probe <dll> <mesh-directory> <cases.tsv> <output.tsv>"); return 2; }
    HMODULE dll = LoadLibraryA(argv[1]);
    if (!dll) { puts("Cannot load 32-bit FFXINAV.dll"); return 2; }
    auto create = (CreateFn)GetProcAddress(dll, "CreateFFXINavClass");
    auto dispose = (DisposeFn)GetProcAddress(dll, "DisposeFFXINavClass");
    auto load = (LoadFn)GetProcAddress(dll, "LoadMesh");
    auto valid = (ValidFn)GetProcAddress(dll, "IsValidPosition");
    auto path = (PathFn)GetProcAddress(dll, "FindClosestPath");
    auto points = (PointsFn)GetProcAddress(dll, "Get_WayPoints");
    if (!create || !dispose || !load || !valid || !path || !points) return 2;
    std::map<std::string, std::string> meshes;
    std::string root(argv[2]);
    WIN32_FIND_DATAA data;
    HANDLE find = FindFirstFileA((root + "\\*.nav").c_str(), &data);
    if (find != INVALID_HANDLE_VALUE) {
        do {
            std::string name(data.cFileName);
            meshes[key(name.substr(0, name.size()-4))] = root + "\\" + name;
        } while (FindNextFileA(find, &data));
        FindClose(find);
    }
    FILE* in = fopen(argv[3], "rb"); FILE* out = fopen(argv[4], "wb");
    if (!in || !out) return 2;
    char buffer[65536];
    if (!fgets(buffer, sizeof(buffer), in)) return 2;
    std::string header(buffer);
    while (!header.empty() && (header.back()=='\r' || header.back()=='\n')) header.pop_back();
    fprintf(out, "%s\tstatus\twaypoints\tstart_snap\tend_snap\tstart_valid\tend_valid\n", header.c_str());
    int zone = -1, total = 0, connected = 0, no_path = 0;
    void* handle = nullptr; bool loaded = false;
    while (fgets(buffer, sizeof(buffer), in)) {
        std::string line(buffer);
        while (!line.empty() && (line.back()=='\r' || line.back()=='\n')) line.pop_back();
        auto c = split(line);
        if (c.size() != 14) { puts("Malformed case row"); return 2; }
        int next = atoi(c[0].c_str());
        if (next != zone) {
            if (handle) dispose(handle);
            zone = next; handle = create(); loaded = false;
            auto mesh = meshes.find(key(c[1]));
            if (handle && mesh != meshes.end()) {
                std::wstring wide(mesh->second.begin(), mesh->second.end());
                loaded = load(handle, wide.c_str());
            }
        }
        Position start = {(float)atof(c[10].c_str()), (float)atof(c[12].c_str()), (float)atof(c[11].c_str())};
        Position end = {(float)atof(c[4].c_str()), (float)atof(c[6].c_str()), (float)atof(c[5].c_str())};
        int count = 0, sv = 0, ev = 0; double ss = -1, es = -1;
        const char* status = "unknown";
        if (loaded) {
            sv = valid(handle, start, false); ev = valid(handle, end, false);
            path(handle, start, end, false);
            Position* wp = nullptr; count = points(handle, &wp);
            if (count > 0 && wp) {
                ss = distance(start, wp[0]); es = distance(end, wp[count-1]);
                // Long single-endpoint results are not routes. Large snapping
                // may jump between floors: leave it unknown, not connected.
                if (count > 1 && ss <= 12 && es <= 12) status = "mesh-connected";
                else if (sv && ev && count <= 1 && distance(start, end) > 12) status = "mesh-no-path";
            }
        }
        ++total;
        if (std::string(status)=="mesh-connected") ++connected;
        if (std::string(status)=="mesh-no-path") ++no_path;
        fprintf(out, "%s\t%s\t%d\t%.3f\t%.3f\t%d\t%d\n", line.c_str(), status, count, ss, es, sv, ev);
    }
    if (handle) dispose(handle);
    fclose(in); if (fclose(out)) return 2;
    printf("Native ingress cases: %d; connected=%d; no-path=%d; unknown=%d\n", total, connected, no_path, total-connected-no_path);
    return 0;
}
