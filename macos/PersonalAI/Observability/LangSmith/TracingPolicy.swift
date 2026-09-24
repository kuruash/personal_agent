import Foundation

enum TracingPolicy {
    static func rootInputs(userMessage: String) -> [String: JSONValue] {
        [
            "input_type": .string("user_message"),
            "character_count": .number(Double(userMessage.count))
        ]
    }

    static func rootMetadata(conversationID: UUID?) -> [String: JSONValue] {
        var metadata: [String: JSONValue] = [
            "provider": .string("nebius"),
            "platform": .string("macOS"),
            "application": .string("PersonalAI")
        ]
        if let conversationID { metadata["conversation_id"] = .string(conversationID.uuidString) }
        return metadata
    }

    static func modelInputs(messageCount: Int, toolCount: Int) -> [String: JSONValue] {
        [
            "operation": .string("chat"),
            "message_count": .number(Double(messageCount)),
            "available_tool_count": .number(Double(toolCount))
        ]
    }

    static func modelMetadata(modelID: String, iteration: Int) -> [String: JSONValue] {
        [
            "provider": .string("nebius"),
            "model": .string(modelID),
            "operation": .string("chat"),
            "iteration": .number(Double(iteration))
        ]
    }

    static func modelOutput(response: ChatCompletionResponse) -> [String: JSONValue] {
        var output: [String: JSONValue] = [
            "choice_count": .number(Double(response.choices.count))
        ]
        if let content = response.choices.first?.message.content {
            output["response_type"] = .string("assistant")
            output["character_count"] = .number(Double(content.count))
        } else if response.choices.first?.message.toolCalls?.isEmpty == false {
            output["response_type"] = .string("tool_call")
            output["tool_call_count"] = .number(Double(response.choices.first?.message.toolCalls?.count ?? 0))
        }
        if let usage = response.usage {
            if let prompt = usage.promptTokens { output["prompt_tokens"] = .number(Double(prompt)) }
            if let completion = usage.completionTokens { output["completion_tokens"] = .number(Double(completion)) }
            if let total = usage.totalTokens { output["total_tokens"] = .number(Double(total)) }
        }
        return output
    }

    static func toolInputs(name: String, arguments: JSONValue?) -> [String: JSONValue] {
        var input: [String: JSONValue] = ["tool_name": .string(name)]
        if case .object(let object) = arguments {
            input["argument_keys"] = .array(object.keys.sorted().map(JSONValue.string))
            if case .string(let path) = object["path"] {
                input["filename"] = .string(URL(fileURLWithPath: path).lastPathComponent)
            }
            if name == "get_profile_section", case .string(let section) = object["section"],
               ProfileSection(rawValue: section) != nil {
                input["requested_section"] = .string(section)
            }
            if name == "search_profile", case .string(let query) = object["query"] {
                input["query_character_count"] = .number(Double(query.count))
            }
            if ["save_memory", "search_memory", "list_memories", "update_memory", "delete_memory"].contains(name) {
                input["operation"] = .string(name)
                if case .string(let type) = object["type"], MemoryType(rawValue: type) != nil {
                    input["memory_type"] = .string(type)
                }
            }
        }
        return input
    }

    static func toolOutput(name: String, result: JSONValue) -> [String: JSONValue] {
        guard case .object(let object) = result else { return ["success": .bool(true)] }
        var output: [String: JSONValue] = ["success": .bool(object["error"] == nil)]
        switch name {
        case "search_files":
            if case .array(let results) = object["results"] {
                output["result_count"] = .number(Double(results.count))
            }
            if let candidates = object["candidateCount"] { output["candidate_count_before_limit"] = candidates }
            if let returned = object["returnedCount"] { output["returned_count"] = returned }
            if let limited = object["limitReached"] { output["limit_reached"] = limited }
            if let sortMode = object["sortMode"] { output["sort_mode"] = sortMode }
        case "list_directory":
            if case .array(let entries) = object["entries"] {
                output["result_count"] = .number(Double(entries.count))
            }
        case "read_file":
            if let bytes = object["returnedBytes"] { output["returned_bytes"] = bytes }
            if let truncated = object["truncated"] { output["truncated"] = truncated }
        case "get_file_info":
            if let bytes = object["sizeBytes"] { output["size_bytes"] = bytes }
        case "get_profile_index":
            if case .array(let sections) = object["available_sections"] {
                output["result_count"] = .number(Double(sections.count))
            }
        case "search_profile":
            if case .array(let results) = object["results"] {
                output["result_count"] = .number(Double(results.count))
            }
        case "get_profile_section":
            output["section_returned"] = .bool(object["error"] == nil)
        case "search_memory", "list_memories":
            if case .array(let results) = object["results"] {
                output["result_count"] = .number(Double(results.count))
            }
        case "save_memory", "update_memory":
            if let status = object["status"] { output["operation_status"] = status }
            if case .object(let memory) = object["memory"],
               case .string(let type) = memory["type"], MemoryType(rawValue: type) != nil {
                output["memory_type"] = .string(type)
            }
        case "delete_memory":
            output["deleted"] = .bool(object["error"] == nil)
        default:
            break
        }
        return output
    }

    static func rootOutput(response: String, modelID: String?) -> [String: JSONValue] {
        var output: [String: JSONValue] = [
            "response_type": .string("assistant"),
            "character_count": .number(Double(response.count))
        ]
        if let modelID { output["model"] = .string(modelID) }
        return output
    }

    static func errorCategory(_ error: Error) -> String {
        switch error {
        case let access as FileAccessError:
            switch access {
            case .accessDenied, .permissionDenied: return "permission_denied"
            case .malformedArguments: return "invalid_arguments"
            default: return "tool_error"
            }
        case AgentRuntimeError.malformedArguments: return "invalid_arguments"
        case AgentRuntimeError.unknownTool: return "unknown_tool"
        case is URLError: return "network_error"
        case is NebiusClientError: return "model_error"
        default: return "unexpected_error"
        }
    }
}
