import downloader.profiles;
import std.stdio;

void main() {
    auto profiles = findChromiumProfiles();
    foreach(p; profiles) {
        writeln(p.browser, " | ", p.name, " | ", p.path);
    }
}
