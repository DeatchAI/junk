import Foundation

struct GitFileTreeNode: Identifiable {
  let path: String
  let name: String
  let file: GitFileChange?
  var children: [GitFileTreeNode]
  var id: String { path }
  var isDirectory: Bool { file == nil }

  static func build(_ files: [GitFileChange]) -> [GitFileTreeNode] {
    func level(_ files: [GitFileChange], prefix: String) -> [GitFileTreeNode] {
      var folders: [String: [GitFileChange]] = [:]
      var nodes: [GitFileTreeNode] = []
      for file in files {
        let remainder = String(file.path.dropFirst(prefix.count))
        if let slash = remainder.firstIndex(of: "/") {
          folders[String(remainder[..<slash]), default: []].append(file)
        } else {
          nodes.append(GitFileTreeNode(path: file.path, name: file.name, file: file, children: []))
        }
      }
      for (name, files) in folders {
        let path = prefix + name
        var node = GitFileTreeNode(path: path, name: name, file: nil, children: level(files, prefix: path + "/"))
        // Compact folders with a single subfolder, while retaining their full identity.
        while node.children.count == 1, let child = node.children.first, child.isDirectory {
          node = GitFileTreeNode(path: child.path, name: node.name + " / " + child.name, file: nil, children: child.children)
        }
        nodes.append(node)
      }
      return nodes.sorted {
        if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
    }
    return level(files, prefix: "")
  }
}

extension GitFileChange {
  var symbol: String {
    switch (name as NSString).pathExtension.lowercased() {
    case "swift": return "swift"
    case "ts", "tsx", "js", "jsx", "json": return "curlybraces"
    case "md", "txt", "rtf": return "doc.text"
    case "css", "scss", "html", "xml", "svg": return "chevron.left.forwardslash.chevron.right"
    case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo"
    case "sh", "bash", "zsh": return "terminal"
    case "yml", "yaml", "toml", "plist": return "slider.horizontal.3"
    default: return "doc"
    }
  }

  var statusSymbol: String {
    if discarded == true { return "↶" }
    switch status {
    case "Added", "Untracked": return "A"
    case "Deleted": return "D"
    case "Renamed": return "R"
    default: return "M"
    }
  }
}
