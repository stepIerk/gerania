import GeraniaCore
import RealtimeKit

/// Tool declarations that the live model can call.
enum LiveTools {
    static let all: [LiveToolDeclaration] = [
        runTask, getTasks, steerTask, cancelTask, cancelAllTasks, getTaskResult, respondApproval,
        finishConversation,
    ]

    static let runTask = LiveToolDeclaration(
        name: "run_task",
        description: """
        Запускает задачу в Hermes: работа с файлами, кодом, терминалом, интернетом,
        поиск и любые действия на компьютере. Верни пользователю короткий ответ,
        что задача запущена, и не жди её завершения.
        """,
        parameters: object(
            properties: [
                "goal": string("Что именно нужно сделать, подробно и по-русски"),
                "title": string("Короткое название задачи для интерфейса"),
            ],
            required: ["goal"]
        )
    )

    static let getTasks = LiveToolDeclaration(
        name: "get_tasks",
        description: "Возвращает список текущих и недавних задач с их статусом.",
        parameters: object(properties: [:], required: [])
    )

    static let steerTask = LiveToolDeclaration(
        name: "steer_task",
        description: "Передаёт уточнение в уже запущенную задачу.",
        parameters: object(
            properties: [
                "task_id": string("Идентификатор задачи"),
                "instruction": string("Что уточнить или изменить"),
            ],
            required: ["task_id", "instruction"]
        )
    )

    static let cancelTask = LiveToolDeclaration(
        name: "cancel_task",
        description: "Останавливает одну задачу.",
        parameters: object(
            properties: ["task_id": string("Идентификатор задачи")],
            required: ["task_id"]
        )
    )

    static let cancelAllTasks = LiveToolDeclaration(
        name: "cancel_all_tasks",
        description: "Останавливает все задачи.",
        parameters: object(properties: [:], required: [])
    )

    static let getTaskResult = LiveToolDeclaration(
        name: "get_task_result",
        description: "Возвращает результат завершённой задачи.",
        parameters: object(
            properties: ["task_id": string("Идентификатор задачи")],
            required: ["task_id"]
        )
    )

    static let finishConversation = LiveToolDeclaration(
        name: "finish_conversation",
        description: """
        Завершает голосовой диалог, когда пользователь попрощался, поблагодарил
        в конце разговора или сказал, что больше ничего не нужно. Сначала коротко
        попрощайся. Не вызывай инструмент, если пользователь задаёт следующий вопрос.
        """,
        parameters: object(properties: [:], required: [])
    )

    static let respondApproval = LiveToolDeclaration(
        name: "respond_approval",
        description: "Подтверждает или отклоняет разрешение либо отвечает на уточнение задачи.",
        parameters: object(
            properties: [
                "request_id": string("Идентификатор запроса"),
                "decision": .object([
                    "type": .string("string"),
                    "description": .string(
                        "once — разрешить один раз, always — разрешить всегда, deny — отклонить"
                    ),
                    "enum": .array([.string("once"), .string("always"), .string("deny")]),
                ]),
                "answer": string("Свободный ответ на уточняющий вопрос задачи"),
            ],
            required: ["request_id"]
        )
    )

    private static func string(_ description: String) -> JSONValue {
        .object([
            "type": .string("string"),
            "description": .string(description),
        ])
    }

    private static func object(
        properties: [String: JSONValue],
        required: [String]
    ) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(JSONValue.string)),
        ])
    }
}
