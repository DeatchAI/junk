import Foundation

@main
struct ConversationTitleTests {
  static func main() throws {
    let update = ConversationTitleUpdate.parse(Data("""
      {"type":"conversation_title","conversationId":"chat-a","title":"Polish Notch Task Controls"}
      """.utf8))!
    var cache = ConversationTitleCache()
    cache.record(update)
    let original = Conversation(id: "chat-a", title: "Please fix the side notch", created_at: 10, updated_at: 20)
    let other = Conversation(id: "chat-b", title: "Another chat", created_at: 30, updated_at: 40)
    let merged = cache.merging([original, other])
    assert(merged[0].title == "Polish Notch Task Controls")
    assert(merged[0].id == original.id && merged[0].updated_at == original.updated_at)
    assert(merged[1].title == other.title, "Only the intended conversation can change")
    assert(cache.merging([original])[0].title == update.title, "An in-flight history response must not undo a live name")
    assert(ConversationTitleUpdate.parse(Data("""
      {"type":"activity","conversationId":"chat-a","title":"Not metadata"}
      """.utf8)) == nil)
    assert(ConversationTitleUpdate.parse(Data("""
      {"type":"conversation_title","conversationId":"","title":"Empty identity"}
      """.utf8)) == nil)
    assert(ConversationTitleUpdate.parse(Data("""
      {"type":"conversation_title","conversationId":"chat-a","title":" "}
      """.utf8)) == nil)
    cache.remove("chat-a")
    assert(cache.merging([original])[0].title == original.title)
    print("Conversation title wire, history merge, identity and ordering checks passed")
  }
}
