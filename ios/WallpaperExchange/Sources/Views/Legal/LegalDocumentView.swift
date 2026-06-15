import SwiftUI

enum LegalDocumentKind: String, CaseIterable, Identifiable {
    case terms
    case privacy
    case dmca

    var id: String { rawValue }

    func title(strings: AppStrings) -> String {
        switch self {
        case .terms: return strings.termsTitle
        case .privacy: return strings.privacyTitle
        case .dmca: return strings.dmcaTitle
        }
    }

    func iconName() -> String {
        switch self {
        case .terms: return "doc.text"
        case .privacy: return "lock.shield"
        case .dmca: return "c.circle"
        }
    }

    func document(strings: AppStrings) -> LegalDoc {
        switch self {
        case .terms:
            return LegalDocs.terms(title: title(strings: strings))
        case .privacy:
            return LegalDocs.privacy(title: title(strings: strings))
        case .dmca:
            return LegalDocs.dmca(title: title(strings: strings))
        }
    }
}

struct LegalDoc {
    let title: String
    let updated: String
    let version: String
    let sections: [LegalSection]
}

struct LegalSection: Identifiable {
    let id: String
    let heading: String
    let paragraphs: [String]
}

struct LegalDocumentView: View {
    let kind: LegalDocumentKind

    @Environment(UIPrefs.self) private var prefs

    var body: some View {
        let strings = L10n.strings(for: prefs.language)
        let doc = kind.document(strings: strings)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(doc, strings: strings)
                ForEach(doc.sections) { section in
                    sectionView(section)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .background(Color.paper)
        .navigationTitle(doc.title)
        .inlineNavTitle()
        .showNavBarCompat()
    }

    private func header(_ doc: LegalDoc, strings: AppStrings) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker(text: "\(strings.legal) · \(doc.version)")
            Text(doc.title)
                .font(.display28)
                .foregroundStyle(Color.ink)
            Text(strings.legalBodyNote)
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                metadataChip(title: strings.lastUpdated, value: doc.updated)
                metadataChip(title: strings.legalVersion, value: doc.version)
            }
        }
        .padding(16)
        .background(Color.paper2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.hair, lineWidth: 1)
        )
    }

    private func metadataChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.mono10)
                .foregroundStyle(Color.muted)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.paper3, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sectionView(_ section: LegalSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(section.id)
                    .font(.mono11)
                    .foregroundStyle(Color.accentInk)
                    .frame(width: 28, alignment: .leading)
                Text(section.heading)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.ink)
            }
            VStack(alignment: .leading, spacing: 9) {
                ForEach(section.paragraphs, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.subheadline)
                        .lineSpacing(4)
                        .foregroundStyle(Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 38)
        }
    }
}

enum LegalDocs {
    static func terms(title: String) -> LegalDoc {
        LegalDoc(
            title: title,
            updated: "May 8, 2026",
            version: "v1.0",
            sections: [
                .init(id: "01", heading: "Acceptance", paragraphs: [
                    "By accessing or using Wallpaper Exchange (\"the Service\"), operated at wallpaperexchange.com, you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the Service.",
                ]),
                .init(id: "02", heading: "The service", paragraphs: [
                    "Wallpaper Exchange is a community-driven platform that allows registered users to upload, share, discover, and download wallpapers. The Service operates on a coin-based exchange system where users earn coins by uploading wallpapers and spend coins to download wallpapers uploaded by others.",
                ]),
                .init(id: "03", heading: "Accounts", paragraphs: [
                    "You must provide accurate information when creating an account.",
                    "You are responsible for maintaining the security of your account credentials.",
                    "You must be at least 13 years of age to use the Service.",
                    "One person may not maintain more than one account.",
                    "We reserve the right to suspend or terminate accounts that violate these terms.",
                ]),
                .init(id: "04", heading: "Your content", paragraphs: [
                    "You retain ownership of content you upload. By uploading, you grant Wallpaper Exchange a non-exclusive, worldwide, royalty-free license to host, display, distribute, and make derivative works (such as thumbnails and device-specific variants) of the content for the purpose of operating the Service.",
                    "You represent and warrant that you own or have the necessary rights to upload the content and that it does not infringe any third party's intellectual property, privacy, or other rights.",
                    "You must not upload content that is illegal, obscene, defamatory, threatening, or otherwise objectionable. We reserve the right to remove any content at our sole discretion without prior notice.",
                ]),
                .init(id: "05", heading: "Copyright & DMCA", paragraphs: [
                    "We respect intellectual property rights. If you believe content on Wallpaper Exchange infringes your copyright, please contact us with: identification of the work, identification of the infringing material and its location, your contact information, a good-faith statement, and a statement under penalty of perjury that the information is accurate.",
                    "Send DMCA notices to dmca@wallpaperexchange.com.",
                ]),
                .init(id: "06", heading: "Coin system", paragraphs: [
                    "Coins are a virtual credit used solely within the Service and have no monetary value. Coins cannot be purchased, sold, transferred, or exchanged for real currency.",
                    "We reserve the right to modify coin values, earning rates, or spending rates at any time. Abuse of the coin system may result in account suspension.",
                ]),
                .init(id: "07", heading: "Prohibited conduct", paragraphs: [
                    "You agree not to upload content you do not have the rights to share, use automated tools to scrape or interact with the Service, circumvent the coin system, redistribute downloaded wallpapers on competing platforms for commercial purposes, harass other users, or interfere with the proper functioning of the Service.",
                ]),
                .init(id: "08", heading: "Disclaimers", paragraphs: [
                    "THE SERVICE IS PROVIDED \"AS IS\" AND \"AS AVAILABLE\" WITHOUT WARRANTIES OF ANY KIND, WHETHER EXPRESS OR IMPLIED, INCLUDING IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.",
                ]),
                .init(id: "09", heading: "Liability", paragraphs: [
                    "TO THE MAXIMUM EXTENT PERMITTED BY LAW, WALLPAPER EXCHANGE AND ITS OPERATORS SHALL NOT BE LIABLE FOR INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES. OUR TOTAL LIABILITY SHALL NOT EXCEED THE AMOUNT YOU HAVE PAID TO US IN THE TWELVE MONTHS PRECEDING THE CLAIM, OR $100 USD, WHICHEVER IS LESS.",
                ]),
                .init(id: "10", heading: "Indemnity", paragraphs: [
                    "You agree to indemnify and hold harmless Wallpaper Exchange, its operators, affiliates, and contributors from any claims, damages, losses, or expenses arising from your use of the Service, your uploaded content, or your violation of these terms.",
                ]),
                .init(id: "11", heading: "Content responsibility", paragraphs: [
                    "Wallpaper Exchange is a platform for user-generated content. We do not pre-screen uploads and are not responsible for content posted by users. User views and content do not represent Wallpaper Exchange.",
                ]),
                .init(id: "12", heading: "Changes", paragraphs: [
                    "We may revise these terms at any time. Changes become effective upon posting. Continued use of the Service after changes constitutes acceptance of the updated terms.",
                ]),
                .init(id: "13", heading: "Termination", paragraphs: [
                    "We may terminate or suspend your access to the Service at any time, without prior notice, for conduct that we believe violates these terms or is harmful to other users or the Service.",
                ]),
                .init(id: "14", heading: "Governing law", paragraphs: [
                    "These terms shall be governed by and construed in accordance with applicable laws, without regard to conflict of law principles. Any disputes shall be resolved in a court of competent jurisdiction.",
                ]),
                .init(id: "15", heading: "Contact", paragraphs: [
                    "If you have questions about these terms, please contact us at support@wallpaperexchange.com.",
                ]),
            ]
        )
    }

    static func privacy(title: String) -> LegalDoc {
        LegalDoc(
            title: title,
            updated: "May 8, 2026",
            version: "v1.0",
            sections: [
                .init(id: "01", heading: "What we collect", paragraphs: [
                    "Account information: when you register, we collect your username, email address, and a hashed version of your password. We do not store plain-text passwords.",
                    "Usage data: we collect information about how you interact with the Service, including uploads, downloads, likes, favorites, and coin transactions.",
                    "Device information: when you use the device-matching feature, your screen resolution is sent to the server to find wallpapers that fit your device. This information is not stored permanently.",
                    "Uploaded content: wallpapers you upload are stored on our servers. Metadata such as resolution, file size, dominant colors, and file type are extracted and stored alongside the image.",
                ]),
                .init(id: "02", heading: "How we use it", paragraphs: [
                    "We use data to operate, maintain, and improve the Service, process coin transactions, generate device-specific wallpaper variants, display your public profile, communicate important updates, enforce our Terms of Service, and prevent abuse.",
                ]),
                .init(id: "03", heading: "Sharing", paragraphs: [
                    "We do not sell, trade, or rent your personal information to third parties.",
                    "Wallpapers you upload and your public profile are visible to all users.",
                    "We may disclose information if required by law, court order, or governmental request.",
                    "We may share data with trusted service providers who help operate the Service, subject to confidentiality obligations.",
                    "We may share information when necessary to protect the rights, safety, or property of the Service, our users, or the public.",
                ]),
                .init(id: "04", heading: "Storage & security", paragraphs: [
                    "Your data is stored on secured servers. We use reasonable technical and organizational measures, including encrypted password storage, secure HTTPS connections, and access controls. No system is completely secure.",
                ]),
                .init(id: "05", heading: "Cookies & local storage", paragraphs: [
                    "We use browser local storage and session storage to maintain your login session, remember preferences, and cache scroll position. We do not use third-party tracking cookies.",
                ]),
                .init(id: "06", heading: "Your rights", paragraphs: [
                    "You may access the personal data we hold about you.",
                    "You may correct inaccurate information in your profile.",
                    "You may delete your uploaded wallpapers at any time.",
                    "You may request account deletion by contacting us. Upon deletion, your personal data and uploaded content will be permanently removed, except where retention is legally required.",
                ]),
                .init(id: "07", heading: "Children", paragraphs: [
                    "The Service is not intended for children under the age of 13. We do not knowingly collect personal information from children under 13.",
                ]),
                .init(id: "08", heading: "Retention", paragraphs: [
                    "We retain your account information and uploaded content for as long as your account is active. If you delete your account, we will delete your personal data within 30 days, except where legally required or needed for legitimate business purposes.",
                ]),
                .init(id: "09", heading: "Changes", paragraphs: [
                    "We may update this Privacy Policy from time to time. Material changes will be posted with an updated last-updated date. Continued use of the Service constitutes acceptance of the updated policy.",
                ]),
                .init(id: "10", heading: "Contact", paragraphs: [
                    "If you have questions about this Privacy Policy or wish to exercise your data rights, please contact us at privacy@wallpaperexchange.com.",
                ]),
            ]
        )
    }

    static func dmca(title: String) -> LegalDoc {
        LegalDoc(
            title: title,
            updated: "2026-05-14",
            version: "v1.0",
            sections: [
                .init(id: "01", heading: "Overview", paragraphs: [
                    "Wallpaper Exchange is a user-driven catalog: anyone with an account can upload wallpapers. We respect intellectual-property rights and respond to credible copyright claims under the U.S. Digital Millennium Copyright Act and equivalent local frameworks.",
                    "If you believe material on this site infringes your copyright, please send a complete notice. We typically remove or restrict access to clearly infringing material within 3 business days of receiving a complete notice.",
                ]),
                .init(id: "02", heading: "Where to send notices", paragraphs: [
                    "Designated copyright agent: copyright@wallpaperexchange.com",
                ]),
                .init(id: "03", heading: "What to include", paragraphs: [
                    "An identification of the copyrighted work you claim has been infringed.",
                    "The URL of the specific wallpaper or wallpapers on Wallpaper Exchange you are asking us to remove.",
                    "Your contact information, including email and physical address.",
                    "A statement that you have a good-faith belief that the use is not authorized by the copyright owner, its agent, or the law.",
                    "A statement, under penalty of perjury, that the information in the notice is accurate and that you are the copyright owner or are authorized to act on the owner's behalf.",
                    "Your physical or electronic signature.",
                ]),
                .init(id: "04", heading: "Counter-notice", paragraphs: [
                    "If you uploaded a wallpaper that was removed and you believe it was a mistake, send a counter-notice to the same address with your identification of the removed material, your contact information, a statement under penalty of perjury that the removal was a mistake or misidentification, and your consent to local-court jurisdiction.",
                ]),
                .init(id: "05", heading: "Repeat infringers", paragraphs: [
                    "Accounts that receive multiple substantiated copyright claims will be terminated.",
                ]),
                .init(id: "06", heading: "In-app reports", paragraphs: [
                    "For other content concerns that are not copyright issues, use the Report button on the wallpaper detail page. Those reports go to the same moderation queue but are handled under community guidelines rather than copyright law.",
                ]),
            ]
        )
    }
}
