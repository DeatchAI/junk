import Foundation

struct HistoryPaginationState: Hashable {
  let bottomY: CGFloat
  let viewportHeight: CGFloat
  let count: Int
  let hasMore: Bool
  let isLoading: Bool
  let isConnected: Bool
  let isSearching: Bool
  let isPresented: Bool

  var shouldLoadMore: Bool {
    isPresented && isConnected && hasMore && !isLoading && !isSearching
      && bottomY.isFinite && viewportHeight > 0 && bottomY >= 0 && bottomY <= viewportHeight + 120
  }
}
