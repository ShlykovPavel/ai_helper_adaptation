import Foundation

@main
enum AskQuestionTests {

    static var failures = 0

    static func check(_ label: String, _ got: String, _ expected: String) {
        if got == expected {
            print("  ✓ \(label)")
        } else {
            print("  ✗ \(label)")
            print("    got:      \(got.debugDescription)")
            print("    expected: \(expected.debugDescription)")
            failures += 1
        }
    }

    static func checkTrue(_ label: String, _ value: Bool) {
        if value { print("  ✓ \(label)") }
        else      { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        let opt1: [String: Any] = ["label": "Postgres", "description": "Full-text search"]
        let opt2: [String: Any] = ["label": "Meilisearch", "description": ""]
        let opt3: [String: Any] = ["label": "Algolia", "description": "Managed search"]

        // ── parse ──────────────────────────────────────────────────────────────
        print("AskQuestion.parse")

        let single: [String: Any] = ["questions": [
            ["question": "Which search engine?", "header": "Search", "options": [opt1, opt2, opt3], "multiSelect": false]
        ]]
        let parsed = AskQuestion.parse(toolInput: single)
        checkTrue("single question parses",           parsed != nil)
        checkTrue("question text",                    parsed?.questions[0].question == "Which search engine?")
        checkTrue("header",                           parsed?.questions[0].header == "Search")
        checkTrue("3 options",                        parsed?.questions[0].options.count == 3)
        checkTrue("multiSelect false",                parsed?.questions[0].multiSelect == false)
        checkTrue("option label",                     parsed?.questions[0].options[0].label == "Postgres")

        // header truncated at 12 chars
        let longHeader: [String: Any] = ["questions": [
            ["question": "Q?", "header": "This is a very long header", "options": [opt1, opt2], "multiSelect": false]
        ]]
        let lh = AskQuestion.parse(toolInput: longHeader)
        checkTrue("header truncated to 12",           lh?.questions[0].header.count == 12)

        // multiSelect true
        let multi: [String: Any] = ["questions": [
            ["question": "Pick features", "header": "Features", "options": [opt1, opt2, opt3], "multiSelect": true]
        ]]
        let mParsed = AskQuestion.parse(toolInput: multi)
        checkTrue("multiSelect true",                 mParsed?.questions[0].multiSelect == true)

        // 4 questions (max)
        let q: [String: Any] = ["question": "Q?", "header": "", "options": [opt1, opt2], "multiSelect": false]
        let four: [String: Any] = ["questions": [q, q, q, q]]
        checkTrue("4 questions parses",               AskQuestion.parse(toolInput: four) != nil)

        // 5 questions → nil (over max)
        let five: [String: Any] = ["questions": [q, q, q, q, q]]
        checkTrue("5 questions → nil",                AskQuestion.parse(toolInput: five) == nil)

        // 1 option → nil (under min)
        let oneOpt: [String: Any] = ["questions": [
            ["question": "Q?", "header": "", "options": [opt1], "multiSelect": false]
        ]]
        checkTrue("1 option → nil",                   AskQuestion.parse(toolInput: oneOpt) == nil)

        // missing question text → nil
        let noQ: [String: Any] = ["questions": [
            ["header": "", "options": [opt1, opt2], "multiSelect": false]
        ]]
        checkTrue("missing question → nil",           AskQuestion.parse(toolInput: noQ) == nil)

        // empty questions array → nil
        checkTrue("empty questions → nil",            AskQuestion.parse(toolInput: ["questions": []]) == nil)

        // missing questions key → nil
        checkTrue("missing questions → nil",          AskQuestion.parse(toolInput: [:]) == nil)

        // option with empty label → nil
        let emptyLabel: [String: Any] = ["questions": [
            ["question": "Q?", "header": "", "options": [["label": "", "description": ""], opt2], "multiSelect": false]
        ]]
        checkTrue("empty option label → nil",         AskQuestion.parse(toolInput: emptyLabel) == nil)

        // ── Antigravity format: options as [String], is_multi_select ────────────
        let agyInput: [String: Any] = [
            "questions": [
                [
                    "question": "Which database engine would you like to use?",
                    "options": ["PostgreSQL", "SQLite", "MySQL"],
                    "is_multi_select": false
                ]
            ]
        ]
        let agyParsed = AskQuestion.parse(toolInput: agyInput)
        checkTrue("Antigravity question parses", agyParsed != nil)
        check("Antigravity question text", agyParsed?.questions.first?.question ?? "", "Which database engine would you like to use?")
        check("Antigravity options count", "\(agyParsed?.questions.first?.options.count ?? 0)", "3")
        check("Antigravity option 1 label", agyParsed?.questions.first?.options[0].label ?? "", "PostgreSQL")
        check("Antigravity option 1 desc empty", agyParsed?.questions.first?.options[0].description ?? "", "")
        checkTrue("Antigravity is_multi_select false", agyParsed?.questions.first?.multiSelect == false)

        let agyMultiInput: [String: Any] = [
            "questions": [
                [
                    "question": "Select target platforms",
                    "options": ["macOS", "iOS", "watchOS"],
                    "is_multi_select": true
                ]
            ]
        ]
        let agyMultiParsed = AskQuestion.parse(toolInput: agyMultiInput)
        checkTrue("Antigravity multi-select parses", agyMultiParsed?.questions.first?.multiSelect == true)

        // Antigravity edge cases:
        // empty string option → nil
        let agyEmptyOpt: [String: Any] = [
            "questions": [
                [
                    "question": "Choose",
                    "options": ["A", ""],
                    "is_multi_select": false
                ]
            ]
        ]
        checkTrue("Antigravity empty option string → nil", AskQuestion.parse(toolInput: agyEmptyOpt) == nil)

        // 1 option → nil
        let agyOneOpt: [String: Any] = [
            "questions": [
                [
                    "question": "Choose",
                    "options": ["OnlyOne"],
                    "is_multi_select": false
                ]
            ]
        ]
        checkTrue("Antigravity 1 option → nil", AskQuestion.parse(toolInput: agyOneOpt) == nil)

        // 5 options → nil
        let agyFiveOpts: [String: Any] = [
            "questions": [
                [
                    "question": "Choose",
                    "options": ["A", "B", "C", "D", "E"],
                    "is_multi_select": false
                ]
            ]
        ]
        checkTrue("Antigravity 5 options → nil", AskQuestion.parse(toolInput: agyFiveOpts) == nil)

        // ── buildAnswers ───────────────────────────────────────────────────────
        print("AskQuestion.buildAnswers")

        let items = AskQuestion.parse(toolInput: multi)!.questions
        + AskQuestion.parse(toolInput: single)!.questions

        // items[0] = "Pick features" (multiSelect: true), items[1] = "Which search engine?" (multiSelect: false)
        let sel1 = [["Postgres"], ["Meilisearch"]]
        let ans1 = AskQuestion.buildAnswers(questions: items, selections: sel1)
        checkTrue("multi-select single pick → [String]",  (ans1["Pick features"] as? [String]) == ["Postgres"])
        checkTrue("single-select answer → String",        (ans1["Which search engine?"] as? String) == "Meilisearch")

        // Multi-select with multiple picks → [String] array
        let sel2 = [["Postgres", "Algolia"], []]
        let ans2 = AskQuestion.buildAnswers(questions: items, selections: sel2)
        checkTrue("multi-select multiple picks → [String]", (ans2["Pick features"] as? [String]) == ["Postgres", "Algolia"])
        checkTrue("unanswered question omitted",            ans2["Which search engine?"] == nil)

        // Empty selections → empty dict
        let ans3 = AskQuestion.buildAnswers(questions: items, selections: [[], []])
        checkTrue("all empty → empty dict",               ans3.isEmpty)

        // ── island height ──────────────────────────────────────────────────────
        print("\nAskQuestion.estimatedIslandHeight")
        let shortQ = AskQuestionItem(question: "Which one?", header: "", options: [
            AskQuestionOption(label: "A", description: ""), AskQuestionOption(label: "B", description: "")
        ], multiSelect: false)
        let longQ = AskQuestionItem(question: String(repeating: "very long question ", count: 12), header: "Test", options: [
            AskQuestionOption(label: "A", description: String(repeating: "explanation ", count: 12)),
            AskQuestionOption(label: "B", description: "short"),
            AskQuestionOption(label: "C", description: "short"),
            AskQuestionOption(label: "D", description: "short")
        ], multiSelect: true)
        checkTrue("chips only → no descriptions",          !shortQ.hasDescriptions)
        checkTrue("one description → vertical list",       longQ.hasDescriptions)
        checkTrue("short question keeps the 160 pt floor", AskQuestion(questions: [shortQ]).estimatedIslandHeight == 160)
        let tall = AskQuestion(questions: [shortQ, longQ]).estimatedIslandHeight
        checkTrue("tallest question wins, within cap",     tall > 160 && tall <= 560)

        // ── finish ─────────────────────────────────────────────────────────────
        if failures == 0 {
            print("\nAll tests passed.")
            exit(0)
        } else {
            print("\n\(failures) test(s) failed.")
            exit(1)
        }
    }
}
