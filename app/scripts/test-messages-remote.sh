#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-messages-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
sources=(
  lazzy/Models/SlashCommand.swift lazzy/Models/AgentModelSettings.swift
  lazzy/Models/ActivityJSONValue.swift lazzy/Models/AgentRunMessages.swift
  lazzy/Models/ConversationBranches.swift lazzy/Models/AgentProvider.swift
  lazzy/Models/AgentQuestion.swift lazzy/Models/MessagesRemoteSettings.swift
  lazzy/UI/DynamicIsland/DetachedRunOutcome.swift
  lazzy/UI/DynamicIsland/DetachedRunProgress.swift
  lazzy/UI/DynamicIsland/DetachedAgentRun.swift
  lazzy/UI/DynamicIsland/DetachedRunStore.swift
  lazzy/UI/DynamicIsland/DetachedRunControls.swift
  lazzy/Core/WebSocket/WebSocketManager+DetachedRuns.swift
  lazzy/Core/Messages/MessagesRPCTransport.swift lazzy/Core/Messages/ImsgRPCClient.swift
  lazzy/Core/Messages/MessagesPairingSession.swift lazzy/Core/Messages/MessagesChatIdentity.swift lazzy/Core/Messages/MessagesQRCode.swift
  lazzy/Core/Messages/MessagesAccountDiscovery.swift lazzy/Core/Messages/MessagesNotificationText.swift
  lazzy/Core/Messages/MessagesDecisionChoices.swift
  lazzy/Core/Messages/MessagesActivityRelay.swift lazzy/Core/Messages/MessagesActivityCommands.swift
  lazzy/Core/Messages/MessagesRemoteController.swift
  lazzy/Core/NativePermissionRequests.swift
  lazzy/Core/Messages/Automation/PollAccessibility.swift
  lazzy/Core/Messages/Automation/PollRequest.swift
  lazzy/Core/Messages/Automation/PollWorkflow.swift
  lazzy/Core/Messages/Polls/MessagesNativePoll.swift
  lazzy/Core/Messages/Polls/MessagesNativePollSender.swift
  lazzy/Core/Messages/Polls/MessagesPollCoordinator.swift
  lazzy/Core/Messages/Polls/MessagesPollDecision.swift
  lazzy/Core/Messages/Polls/MessagesPollSending.swift
  tests/messages/MessagesTestSupport.swift tests/messages/MessagesRemoteTests.swift
  tests/messages/MessagesDecisionTests.swift tests/messages/MessagesAuthorizationTests.swift
  tests/messages/polls/MessagesPollTestSupport.swift tests/messages/polls/MessagesPollTests.swift
  tests/messages/polls/MessagesPollRecoveryTests.swift
  tests/messages/polls/MessagesQuestionPollTests.swift tests/messages/polls/MessagesPollIdentityTests.swift
)
for index in "${!sources[@]}"; do sources[index]="$app_root/${sources[index]}"; done
xcrun swiftc -swift-version 5 -D DEBUG -default-isolation MainActor -module-cache-path "$test_dir/modules" \
  "${sources[@]}" -o "$test_dir/messages-tests"
"$test_dir/messages-tests"
