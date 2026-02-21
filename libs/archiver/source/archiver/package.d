module archiver;

import std.stdio;
import std.file;
import std.path;
import std.algorithm;
import std.array;
import std.uri;
import std.net.curl;
import std.conv;
import std.typecons;
import std.string;

import requests;
import arsd.dom;

/**
    SiteArchiver handles downloading a website recursively and rewriting links.
*/
class SiteArchiver {
    string rootUrl;
    string outputDir;
    string domain;
    bool[string] visitedUrls;

    this(string rootUrl, string outputDir) {
        this.rootUrl = rootUrl;
        this.outputDir = outputDir;
        // Simple domain extraction
        auto u = URI(rootUrl);
        this.domain = getApexDomain(u.host);
    }

    private string getApexDomain(string host) {
        if (host.startsWith("www.")) return host[4..$];
        return host;
    }

    void archive(int maxDepth = 3) {
        crawl(rootUrl, 0, maxDepth);
    }

    private void crawl(string url, int currentDepth, int maxDepth) {
        if (currentDepth > maxDepth || url in visitedUrls) return;
        visitedUrls[url] = true;

        writeln("Archiving: ", url);

        try {
            auto req = Request();
            req.verbosity = 0;
            req.sslSetVerifyPeer(false); // Allow insecure for archiving
            auto rs = req.get(url);
            
            // If redirected, mark the final URL as visited too to prevent loops
            string finalUrl = rs.finalURI.uri;
            if (finalUrl != url) {
                visitedUrls[finalUrl] = true;
            }

            string contentType = rs.responseHeaders.get("Content-Type", "text/html");

            string localPath = urlToLocalPath(finalUrl);
            string fullPath = buildPath(outputDir, localPath);
            mkdirRecurse(dirName(fullPath));

            if (contentType.canFind("text/html")) {
                string html = rs.responseBody.toString();
                auto document = new Document(html);

                // Process links
                foreach(element; document.querySelectorAll("a, link, img, script")) {
                    string attr = "";
                    if (element.tagName == "a" || element.tagName == "link") attr = "href";
                    else if (element.tagName == "img" || element.tagName == "script") attr = "src";

                    if (!attr.empty && element.hasAttribute(attr)) {
                        string targetUrl = element.getAttribute(attr);
                        string absoluteTarget = resolveUrl(finalUrl, targetUrl);

                        if (shouldDownload(absoluteTarget)) {
                            // Recursively crawl if it's a link and we have depth
                            if (element.tagName == "a" && currentDepth < maxDepth) {
                                crawl(absoluteTarget, currentDepth + 1, maxDepth);
                            }

                            // Rewrite link to local relative path
                            string localTarget = urlToLocalPath(absoluteTarget);
                            element.setAttribute(attr, getRelativePath(localPath, localTarget));
                        }
                    }
                }

                std.file.write(fullPath, document.toString());
            } else {
                // Non-HTML content (images, css, etc.)
                std.file.write(fullPath, rs.responseBody.data);
            }
        } catch (Exception e) {
            writeln("Error archiving ", url, ": ", e.msg);
        }
    }

    private string resolveUrl(string base, string relative) {
        if (relative.empty || relative.startsWith("#")) return base;
        if (relative.startsWith("http")) return relative;
        
        auto u = URI(base);
        if (relative.startsWith("/")) {
            return u.scheme ~ "://" ~ u.host ~ relative;
        }
        
        // Handle relative paths (not starting with /)
        string basePath = u.path;
        if (!basePath.endsWith("/")) {
            auto lastSlash = basePath.lastIndexOf("/");
            if (lastSlash != -1) basePath = basePath[0..lastSlash+1];
            else basePath = "/";
        }
        
        return u.scheme ~ "://" ~ u.host ~ basePath ~ relative;
    }

    private bool shouldDownload(string url) {
        auto u = URI(url);
        string targetDomain = getApexDomain(u.host);
        return targetDomain == this.domain || targetDomain.endsWith("." ~ this.domain);
    }

    private string urlToLocalPath(string url) {
        auto u = URI(url);
        string path = u.path;
        
        // Strip fragment
        import std.algorithm.searching : countUntil;
        auto hashIdx = path.countUntil("#");
        if (hashIdx != -1) path = path[0..hashIdx];
        
        // Strip leading slash
        if (path.startsWith("/")) path = path[1..$];
        
        // Handle empty path or directory-like path
        if (path.empty) path = "index.html";
        else if (path.endsWith("/")) path ~= "index.html";
        
        // Ensure extension if missing
        if (!path.canFind(".")) path ~= ".html";

        // Sanitize for Windows: remove query/fragment and replace invalid chars
        import std.string : tr;
        path = path.tr(`<>:"|?*#`, `________`);
        
        return buildPath(u.host, path);
    }

    private string getRelativePath(string from, string to) {
        // Simplified relative path calculation
        return to; // For now
    }
}
