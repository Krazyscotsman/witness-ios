import Foundation

// MARK: - Activation prompts (Home's floating cycling invitation).
// The model is intentionally small and data-driven so the list below can be edited freely
// without touching the cycle/retire/evolve logic in HomeActivationViewModel.
//
// Vocabulary (per product decision):
//   • kind          — a category of memory. "Retire-after-2" is tracked PER KIND: once the user
//                     has recorded 2 memories of a kind, every prompt of that kind is retired.
//   • form          — how a prompt behaves as it's used:
//       - .singular   asked once with `text`; after its first use it EVOLVES to `repeatVariant`
//                     and keeps recurring (as the variant) until its kind hits 2.
//       - .repeatable recurs as-is until its kind hits 2.
//       - .parent     evergreen; never retired, never counts toward retirement. The always-present
//                     "You decide what to share…" invitation uses this so the cycle is never empty.
//   • text          — the primary phrasing shown.
//   • repeatVariant — the softer "again" phrasing a singular switches to after first use.
//
// Note on the "parenthood" prompts: they are a normal category (kind "child") — one singular that
// evolves, two repeatable — so they honour retire-after-2 like any other kind. Only "You decide…"
// is truly evergreen (form .parent).

enum PromptForm {
    case singular
    case repeatable
    case parent
}

struct ActivationPrompt: Identifiable, Equatable {
    let id: String
    let kind: String
    let form: PromptForm
    let text: String
    let repeatVariant: String?

    init(id: String, kind: String, form: PromptForm, text: String, repeatVariant: String? = nil) {
        self.id = id
        self.kind = kind
        self.form = form
        self.text = text
        self.repeatVariant = repeatVariant
    }
}

enum ActivationPrompts {
    // The always-present open invitation. Parent form → never retired, always in the cycle.
    static let youDecide = ActivationPrompt(
        id: "you-decide", kind: "open", form: .parent,
        text: "You decide what to share…"
    )

    static let all: [ActivationPrompt] = [
        // MARK: Singular (evolve to repeatVariant after first use)
        ActivationPrompt(
            id: "love-of-life", kind: "people", form: .singular,
            text: "Tell me about the love of your life.",
            repeatVariant: "Tell me about another person you've loved."
        ),
        ActivationPrompt(
            id: "best-friend", kind: "friends", form: .singular,
            text: "Tell me about the best friend of your life.",
            repeatVariant: "Tell me about another friend who mattered."
        ),
        ActivationPrompt(
            id: "proudest-moment", kind: "pride", form: .singular,
            text: "What's the proudest moment of your life?",
            repeatVariant: "Tell me about another moment you were proud."
        ),
        ActivationPrompt(
            id: "happiest-day", kind: "joy", form: .singular,
            text: "What was the happiest day of your life?",
            repeatVariant: "Tell me about another day full of joy."
        ),
        ActivationPrompt(
            id: "saddest-day", kind: "loss", form: .singular,
            text: "What was the saddest day of your life?",
            repeatVariant: "Tell me about another time of loss."
        ),
        ActivationPrompt(
            id: "life-changed", kind: "turning_point", form: .singular,
            text: "Tell me about the day your life changed forever.",
            repeatVariant: "Tell me about another turning point."
        ),

        // MARK: Repeatable
        ActivationPrompt(
            id: "fear", kind: "fear", form: .repeatable,
            text: "Tell me about a time you were truly afraid."
        ),
        ActivationPrompt(
            id: "influence", kind: "influence", form: .repeatable,
            text: "Who shaped who you are today?"
        ),
        ActivationPrompt(
            id: "moment", kind: "moment", form: .repeatable,
            text: "Tell me about a moment you'll never forget."
        ),
        ActivationPrompt(
            id: "laughter", kind: "laughter", form: .repeatable,
            text: "What's a memory that still makes you laugh?"
        ),
        ActivationPrompt(
            id: "place", kind: "place", form: .repeatable,
            text: "Tell me about a place that means something to you."
        ),
        ActivationPrompt(
            id: "missed", kind: "missed", form: .repeatable,
            text: "Tell me about someone you miss."
        ),
        ActivationPrompt(
            id: "resilience", kind: "resilience", form: .repeatable,
            text: "What's something you overcame?"
        ),

        // MARK: Parenthood (kind "child" — retires after 2 like any other kind)
        ActivationPrompt(
            id: "child-born", kind: "child", form: .singular,
            text: "Tell me about the day your child was born.",
            repeatVariant: "Tell me about another of your children's beginnings."
        ),
        ActivationPrompt(
            id: "child-unforgettable", kind: "child", form: .repeatable,
            text: "What's something your child did that you never want to forget?"
        ),
        ActivationPrompt(
            id: "child-first-laugh", kind: "child", form: .repeatable,
            text: "Tell me about the first time your child made you laugh."
        ),

        // MARK: Evergreen (always present, never retires)
        youDecide,
    ]
}
