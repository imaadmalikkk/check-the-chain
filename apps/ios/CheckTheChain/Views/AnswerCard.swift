import SwiftUI
import HadithKit

/// A generated summary, and the disclaimer that belongs to it.
///
/// The disclaimer sits inside the card rather than at the foot of the screen
/// on purpose. It qualifies *this paragraph* — the one piece of text in the
/// app that no scholar wrote and no collection published — and a caveat the
/// reader has to scroll to find is a caveat aimed at the developer's
/// conscience rather than at them.
struct AnswerCard: View {
    let answer: Answer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(answer.summary)
                .font(.body)
                .foregroundStyle(Palette.inkBody)
                .lineSpacing(6)
                .textSelection(.enabled)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                Text("Written by the on-device model from the narrations below. It is not a scholarly ruling — read them yourself.")
            }
            .font(.caption)
            .foregroundStyle(Palette.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityIdentifier("answerCard")
    }
}

/// Why the Ask affordance is visible but cannot run.
///
/// Only the two states the reader can do something about get a message.
/// `ineligibleDevice` never reaches here — the affordance is not drawn at all
/// on hardware that cannot run the model, because a permanently dead control
/// is worse than no control.
struct AnswerUnavailableNote: View {
    let availability: AnswerEngine.Availability

    var body: some View {
        if let message {
            Text(message)
                .font(.caption)
                .foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.center)
        }
    }

    private var message: String? {
        switch availability {
        case .appleIntelligenceOff:
            "Ask needs Apple Intelligence, which is switched off. You can turn it on in Settings."
        case .modelDownloading:
            "Ask will be ready once Apple Intelligence finishes downloading."
        case .available, .ineligibleDevice:
            nil
        }
    }
}
