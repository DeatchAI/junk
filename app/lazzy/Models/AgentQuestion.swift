import Foundation

struct AgentQuestion: Decodable, Equatable, Identifiable {
  struct Option: Decodable, Equatable {
    let label: String
    let description: String?
  }
  let id: String
  let header: String
  let question: String
  let options: [Option]?
  let isSecret: Bool?
}

struct AgentQuestionEnvelope: Decodable, Equatable, Identifiable {
  let id: String
  let runId: String
  let conversationId: String
  let agent: String
  let taskTitle: String?
  let questions: [AgentQuestion]
}

struct AgentQuestionResponse: Encodable {
  struct Answer: Encodable { let answers: [String] }
  let type = "agent_question_response"
  let requestId: String
  let runId: String
  let answers: [String: Answer]?
  let cancelled: Bool
}
