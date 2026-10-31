import AppKit
import SwiftUI

struct GitFileNavigator: View {
  let files: [GitFileChange]
  @Binding var selection: String?
  @State private var collapsed = Set<String>()
  @ObservedObject private var theme = ThemeManager.shared

  private struct Entry: Identifiable {
    let node: GitFileTreeNode
    let depth: Int
    var id: String { node.id }
  }

  private var entries: [Entry] {
    func flatten(_ nodes: [GitFileTreeNode], depth: Int) -> [Entry] {
      nodes.flatMap { node in
        [Entry(node: node, depth: depth)] + (collapsed.contains(node.path) ? [] : flatten(node.children, depth: depth + 1))
      }
    }
    return flatten(GitFileTreeNode.build(files), depth: 0)
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Files changed").font(.appFont(size: 11, weight: .medium))
        Spacer()
        Text("\(files.count)").font(.appFont(size: 10)).monospacedDigit()
      }.foregroundStyle(theme.secondaryTextColor).padding(.horizontal, 14).frame(height: 38)
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 2) {
            ForEach(entries) { entry in
              row(entry).id(entry.id)
            }
          }.padding(.horizontal, 6).padding(.bottom, 12)
        }
        .onChange(of: selection) { _, path in
          guard let path else { return }
          collapsed = collapsed.filter { !path.hasPrefix($0 + "/") }
          withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(path) }
        }
      }
    }.background(theme.textColor.opacity(0.018))
  }

  private func row(_ entry: Entry) -> some View {
    let node = entry.node, selected = node.file != nil && selection == node.path
    return Button {
      if node.isDirectory {
        if !collapsed.insert(node.path).inserted { collapsed.remove(node.path) }
      } else { selection = node.path }
    } label: {
      HStack(spacing: 7) {
        Image(systemName: node.isDirectory ? (collapsed.contains(node.path) ? "chevron.right" : "chevron.down") : "")
          .font(.system(size: 8, weight: .semibold)).frame(width: 8).opacity(node.isDirectory ? 1 : 0)
        Image(systemName: node.file?.symbol ?? (collapsed.contains(node.path) ? "folder" : "folder.fill"))
          .font(.system(size: 12)).frame(width: 15)
          .foregroundStyle(Color(nsColor: node.file.map { theme.gitReviewPalette.icon(for: $0) } ?? theme.gitReviewPalette.blue))
        Text(node.name).font(.appFont(size: 12, weight: selected ? .medium : .regular))
          .lineLimit(1).truncationMode(.middle)
          .foregroundStyle(node.file.map { Color(nsColor: theme.gitReviewPalette.status(for: $0)) } ?? theme.textColor)
        Spacer(minLength: 2)
        if let file = node.file {
          Text(file.statusSymbol).font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(nsColor: theme.gitReviewPalette.status(for: file)))
        }
      }
      .padding(.leading, 6 + CGFloat(entry.depth) * 12).padding(.trailing, 9).frame(height: 29)
      .background(selected ? theme.textColor.opacity(0.085) : .clear, in: RoundedRectangle(cornerRadius: 5))
      .contentShape(Rectangle())
    }.buttonStyle(.plain).help(node.path)
      .accessibilityLabel(node.file.map { "\($0.name), \($0.status), \($0.counts)" } ?? "\(node.name), folder")
      .accessibilityValue(node.isDirectory ? (collapsed.contains(node.path) ? "Collapsed" : "Expanded") : (selected ? "Selected" : ""))
  }
}

struct GitFileTabs: View {
  let files: [GitFileChange]
  @Binding var selection: String?
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 0) {
          ForEach(files) { file in
            Button { selection = file.path } label: {
              HStack(spacing: 7) {
                Image(systemName: file.symbol).font(.system(size: 12)).foregroundStyle(Color(nsColor: theme.gitReviewPalette.icon(for: file)))
                Text(file.name).font(.appFont(size: 12)).lineLimit(1).foregroundStyle(Color(nsColor: theme.gitReviewPalette.status(for: file)))
                Text(file.statusSymbol).font(.system(size: 9, design: .monospaced)).foregroundStyle(Color(nsColor: theme.gitReviewPalette.status(for: file)))
              }
              .padding(.horizontal, 14).frame(height: 38)
              .background(selection == file.path ? theme.solidBackground : theme.textColor.opacity(0.025))
              .overlay(alignment: .bottom) {
                if selection == file.path { Color(nsColor: theme.gitReviewPalette.status(for: file)).frame(height: 1.5) }
              }
              .overlay(alignment: .trailing) { theme.textColor.opacity(0.08).frame(width: 1) }
              .contentShape(Rectangle())
            }.buttonStyle(.plain).help(file.path).id(file.path)
              .accessibilityLabel("\(file.path), \(file.status)")
              .accessibilityAddTraits(selection == file.path ? .isSelected : [])
          }
        }
      }
      .onChange(of: selection) { _, path in
        if let path { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(path) } }
      }
    }.frame(height: 38)
  }
}

struct GitReviewIconButton: View {
  let symbol: String
  let label: String
  var action: () -> Void
  @State private var hovering = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 27, height: 27)
        .foregroundStyle(theme.secondaryTextColor)
        .background(hovering ? theme.textColor.opacity(0.075) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
    }.buttonStyle(.plain).help(label).accessibilityLabel(label).onHover { hovering = $0 }
  }
}

struct GitWindowDragRegion: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView { DragView() }
  func updateNSView(_ view: NSView, context: Context) {}
  private final class DragView: NSView {
    override func mouseDown(with event: NSEvent) {
      if event.clickCount == 2 { window?.zoom(nil) } else { window?.performDrag(with: event) }
    }
  }
}
