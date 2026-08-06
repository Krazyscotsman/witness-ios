import SwiftUI

// MARK: - Legal pages (web: /privacy, /security, /terms). Faithful to the source,
// including the draft banner. Static content; no endpoint.
enum LegalDoc: String, Identifiable {
    case privacy, security, terms
    var id: String { rawValue }

    var title: String {
        switch self { case .privacy: return "Privacy"; case .security: return "Security"; case .terms: return "Terms of Service" }
    }
    var icon: String {
        switch self { case .privacy: return "hand.raised"; case .security: return "lock.shield"; case .terms: return "doc.text" }
    }
    var sections: [LegalSection] {
        switch self {
        case .privacy:
            return [
                .init("Our promise", "Witness exists to preserve your life, and we treat that as a sacred trust. Your memories are yours. We do not sell them, we do not share them, and we do not use them to train AI models — not ours, not anyone’s."),
                .init("What we collect", "The memories you choose to share (typed or spoken), the account details needed to sign you in, and basic technical data required to operate the service. We collect nothing beyond what the product needs to work for you."),
                .init("How your memories are protected", "Your memories are encrypted at rest and in transit. Access is limited to the systems required to provide the features you use. [Confirm specific standards here once verified — e.g. AES-256 at rest, TLS 1.3 in transit — and state only what is actually deployed.]"),
                .init("Your control", "You can view, export, and permanently delete your memories at any time. When you delete a memory, it is removed from the active system, and the understanding derived from it is removed on our regular processing cycle."),
                .init("Third parties", "Witness uses a small number of service providers to operate (for example, hosting and the AI processing that parses your memories). These providers process data only to deliver the service and are bound not to use it for their own purposes. [List actual sub-processors here once finalized.]"),
                .init("Changes", "If this policy changes in a way that affects how your memories are handled, we will tell you before the change takes effect."),
            ]
        case .security:
            return [
                .init("How we think about security", "Witness holds the most personal data a person has. Protecting it is the foundation of the product, not a feature. We design so that the smallest possible number of systems can ever touch your memories."),
                .init("Encryption", "Your data is encrypted in transit and at rest. [State exact standards only once deployed and verified — e.g. TLS 1.3 in transit, AES-256 at rest. Do not claim protection that is not live.]"),
                .init("Access", "Access to systems handling your memories is restricted and logged. [Security review to detail access controls.]"),
                .init("Data ownership", "Your memories are never sold and never used to train AI. You can export or permanently delete them at any time."),
                .init("Reporting an issue", "Found a security concern? Email us and we will respond quickly: security@morynsystems.com. [Confirm inbox.]"),
            ]
        case .terms:
            return [
                .init("Agreement", "By using Witness you agree to these terms. [Counsel to complete.]"),
                .init("Your account", "You are responsible for keeping your sign-in secure. You must be of legal age in your jurisdiction to use Witness."),
                .init("Your content", "Your memories remain yours. You grant Witness only the limited permission needed to store, process, and present them back to you as part of the service. We claim no ownership of your life."),
                .init("Acceptable use", "Use Witness for your own memories and lawful purposes. [Counsel to specify prohibited uses.]"),
                .init("Payment", "Your first ten memory parsings are free. [Counsel and final pricing to complete billing, renewal, and refund terms.]"),
                .init("Disclaimers and liability", "[Counsel to complete — warranty disclaimers, limitation of liability, governing law.]"),
                .init("Termination", "You may stop using Witness and delete your data at any time. [Counsel to complete suspension and termination terms.]"),
            ]
        }
    }
}

struct LegalSection: Identifiable {
    let id = UUID()
    let heading: String
    let body: String
    init(_ heading: String, _ body: String) { self.heading = heading; self.body = body }
}

struct LegalView: View {
    let doc: LegalDoc
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(doc.title).font(.serif(30)).foregroundStyle(WT.ink)
                        Text("Last updated: [date]").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.45))
                    }
                    draftBanner
                    ForEach(doc.sections) { s in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(s.heading).font(.serif(19)).foregroundStyle(WV.teal)
                            Text(s.body).font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.8))
                                .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 40)
            }
            navBar
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
    }

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)); Text("Back").font(.system(size: 16)) }
                    .foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress()
            Spacer()
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }

    private var draftBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14)).foregroundStyle(WV.gold).padding(.top, 1)
            Text("Draft — placeholder language, not legal advice. Review and replace with counsel-approved text before public launch or accepting payment.")
                .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.65)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WV.gold.opacity(0.3), lineWidth: 1))
    }
}
