module archiver.profiles;

import std.file;
import std.path;
import std.process;
import std.stdio;
import std.json;

struct BrowserProfile {
    string name;
    string path;
    string browser;
}

BrowserProfile[] findChromiumProfiles() {
    BrowserProfile[] profiles;
    string localAppData = environment.get("LOCALAPPDATA");
    
    // Chrome
    string chromePath = buildPath(localAppData, "Google", "Chrome", "User Data");
    if (exists(chromePath)) {
        profiles ~= scanDir(chromePath, "Chrome");
    }

    // Edge
    string edgePath = buildPath(localAppData, "Microsoft", "Edge", "User Data");
    if (exists(edgePath)) {
        profiles ~= scanDir(edgePath, "Edge");
    }

    return profiles;
}

private BrowserProfile[] scanDir(string path, string browser) {
    BrowserProfile[] found;
    
    // First, try to read the Local State file to get display names
    string[string] profileNames;
    string localStatePath = buildPath(path, "Local State");
    if (exists(localStatePath)) {
        try {
            auto content = readText(localStatePath);
            auto json = parseJSON(content);
            if ("profile" in json.object && "info_cache" in json.object["profile"].object) {
                auto cache = json.object["profile"].object["info_cache"].object;
                foreach(dirName, info; cache) {
                    if ("shortcut_name" in info.object) {
                        profileNames[dirName] = info.object["shortcut_name"].str;
                    } else if ("name" in info.object) {
                        profileNames[dirName] = info.object["name"].str;
                    }
                }
            }
        } catch (Exception e) {}
    }

    foreach(DirEntry entry; dirEntries(path, SpanMode.shallow)) {
        if (entry.isDir) {
            string profilePath = entry.name;
            string prefPath = buildPath(profilePath, "Preferences");
            if (exists(prefPath)) {
                string dirName = baseName(profilePath);
                string name = dirName;
                
                // Use Local State name if available
                if (dirName in profileNames) {
                    name = profileNames[dirName];
                } else {
                    // Fallback to reading Preferences directly
                    try {
                        auto content = readText(prefPath);
                        auto json = parseJSON(content);
                        if ("profile" in json.object && "name" in json.object["profile"].object) {
                            name = json.object["profile"].object["name"].str;
                        }
                    } catch (Exception e) {}
                }
                
                found ~= BrowserProfile(name, profilePath, browser);
            }
        }
    }
    return found;
}

