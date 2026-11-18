import Foundation

/// A ready-made schedule, shown as a button in the «Планы» tab.
public struct PlanTemplate: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let schedule: String
    public let prompt: String
    public let symbol: String

    public init(
        id: String,
        title: String,
        subtitle: String,
        schedule: String,
        prompt: String,
        symbol: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.schedule = schedule
        self.prompt = prompt
        self.symbol = symbol
    }
}

/// The six starters from the roadmap, plus the morning brief.
///
/// The schedule strings follow the `hermes cron` grammar: `30m`/`every 2h` are
/// intervals, `in 2h` is a one-shot delay, `0 8 * * *` is a cron expression.
/// Every field stays editable in the create sheet.
public enum PlanTemplates {
    public static let all: [PlanTemplate] = [
        PlanTemplate(
            id: "morning-brief",
            title: "Утренний брифинг",
            subtitle: "Календарь, погода и дедлайны на день",
            schedule: "0 8 * * *",
            prompt: "Собери короткий утренний брифинг: сегодняшние события календаря, погода, "
                + "дедлайны и напоминания. Учти расписание пользователя из USER.md. "
                + "Если календарь не подключён — предложи подключить. Пиши кратко, списком.",
            symbol: "sunrise"
        ),
        PlanTemplate(
            id: "workday-start",
            title: "Начало рабочего дня",
            subtitle: "Три главные задачи по будням",
            schedule: "0 9 * * 1-5",
            prompt: "Составь план на рабочий день: три главные задачи, что проверить и где может "
                + "понадобиться помощь. Опирайся на заметки в памяти.",
            symbol: "briefcase"
        ),
        PlanTemplate(
            id: "custom-reminder",
            title: "Напоминание",
            subtitle: "Один раз в нужный момент",
            schedule: "in 2h",
            prompt: "Напомни о важном деле и коротко скажи, что с ним сделать.",
            symbol: "bell"
        ),
        PlanTemplate(
            id: "weekly-review",
            title: "Недельный обзор",
            subtitle: "Итоги недели по воскресеньям",
            schedule: "0 19 * * 0",
            prompt: "Собери недельный обзор: что сделано, что осталось, что перенести на "
                + "следующую неделю. Коротко, списком.",
            symbol: "calendar"
        ),
        PlanTemplate(
            id: "learn-daily",
            title: "Учёба каждый день",
            subtitle: "Небольшое задание по стеку",
            schedule: "0 18 * * 1-5",
            prompt: "Предложи короткое учебное задание по моему стеку на 20–30 минут и объясни, "
                + "зачем оно. Опирайся на USER.md.",
            symbol: "graduationcap"
        ),
        PlanTemplate(
            id: "news-digest",
            title: "Дайджест новостей",
            subtitle: "Пять ссылок по технологиям",
            schedule: "0 9 * * *",
            prompt: "Собери короткий дайджест новостей по технологиям и моему стеку. Пять пунктов "
                + "со ссылками, без воды.",
            symbol: "newspaper"
        ),
    ]
}
