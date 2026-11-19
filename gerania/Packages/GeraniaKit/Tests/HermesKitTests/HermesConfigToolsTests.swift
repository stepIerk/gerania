import HermesKit
import Testing

@Suite("Подсказка инструментов")
struct HermesConfigToolsTests {
    @Test("Каждый запрос ведёт агента к computer_use, а не к browser_cdp")
    func hintGoesFirst() {
        let config = HermesConfig(voicePromptPrefix: "[Голос] ", textPromptPrefix: "[Текст] ")

        let voice = config.prompt(for: "открой сайт", mode: .voice)
        let text = config.prompt(for: "открой сайт", mode: .text)

        #expect(voice == HermesConfig.toolRoutingHint + "[Голос] открой сайт")
        #expect(text == HermesConfig.toolRoutingHint + "[Текст] открой сайт")
        #expect(HermesConfig.toolRoutingHint.contains("computer_use"))
    }
}
