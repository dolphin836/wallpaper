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

    func document(strings: AppStrings, language: AppLanguage) -> LegalDoc {
        switch self {
        case .terms:
            return LegalDocs.terms(title: title(strings: strings), language: language.resolved)
        case .privacy:
            return LegalDocs.privacy(title: title(strings: strings), language: language.resolved)
        case .dmca:
            return LegalDocs.dmca(title: title(strings: strings), language: language.resolved)
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
        let doc = kind.document(strings: strings, language: prefs.language)

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
    static func terms(title: String, language: AppLanguage) -> LegalDoc {
        switch language {
        case .zhHans, .system:
            return LegalDoc(title: title, updated: "2026 年 5 月 8 日", version: "v1.0", sections: [
                .init(id: "01", heading: "接受条款", paragraphs: [
                    "访问或使用由 wallpaperexchange.com 提供的 Wallpaper Exchange 服务，即表示你同意受本服务条款约束。如果你不同意这些条款，请不要使用本服务。",
                ]),
                .init(id: "02", heading: "服务说明", paragraphs: [
                    "Wallpaper Exchange 是一个由社区驱动的平台，允许注册用户上传、分享、发现和下载壁纸。本服务使用金币交换机制，用户通过上传壁纸获得金币，并使用金币下载其他用户上传的壁纸。",
                ]),
                .init(id: "03", heading: "账户", paragraphs: [
                    "创建账户时，你必须提供准确的信息。",
                    "你需要自行负责账户凭据的安全。",
                    "你必须年满 13 周岁才能使用本服务。",
                    "同一自然人不得维护多个账户。",
                    "我们保留暂停或终止违反本条款账户的权利。",
                ]),
                .init(id: "04", heading: "你的内容", paragraphs: [
                    "你保留所上传内容的所有权。上传内容即表示你授予 Wallpaper Exchange 一项非独占、全球范围、免版税的许可，用于托管、展示、分发并制作缩略图、设备适配版本等衍生内容，以便运营本服务。",
                    "你声明并保证你拥有上传该内容所需的权利，且该内容不会侵犯任何第三方的知识产权、隐私权或其他权利。",
                    "你不得上传违法、淫秽、诽谤、威胁或其他不适当内容。我们可自行决定移除任何内容，且无需提前通知。",
                ]),
                .init(id: "05", heading: "版权与 DMCA", paragraphs: [
                    "我们尊重知识产权。如果你认为 Wallpaper Exchange 上的内容侵犯了你的版权，请向我们提供作品说明、侵权材料及其位置、你的联系方式、善意声明，以及在伪证责任下确认信息准确的声明。",
                    "DMCA 通知请发送至 dmca@wallpaperexchange.com。",
                ]),
                .init(id: "06", heading: "金币系统", paragraphs: [
                    "金币是仅可在本服务内使用的虚拟积分，不具有货币价值。金币不可购买、出售、转让或兑换为真实货币。",
                    "我们可随时调整金币价值、获得规则或消耗规则。滥用金币系统可能导致账户被暂停。",
                ]),
                .init(id: "07", heading: "禁止行为", paragraphs: [
                    "你不得上传无权分享的内容，不得使用自动化工具抓取或操作本服务，不得规避金币系统，不得将下载的壁纸在竞争平台上用于商业再分发，不得骚扰其他用户，也不得干扰本服务的正常运行。",
                ]),
                .init(id: "08", heading: "免责声明", paragraphs: [
                    "本服务按“现状”和“可用”提供，不作任何明示或默示保证，包括但不限于适销性、特定用途适用性和不侵权保证。",
                ]),
                .init(id: "09", heading: "责任限制", paragraphs: [
                    "在法律允许的最大范围内，Wallpaper Exchange 及其运营方不对任何间接、附带、特殊、后果性或惩罚性损害负责。我们的总责任不超过你在索赔前十二个月向我们支付的金额，或 100 美元，以较低者为准。",
                ]),
                .init(id: "10", heading: "赔偿", paragraphs: [
                    "对于因你使用本服务、上传内容或违反本条款而引起的任何索赔、损害、损失或费用，你同意赔偿并使 Wallpaper Exchange、其运营方、关联方和贡献者免受损害。",
                ]),
                .init(id: "11", heading: "内容责任", paragraphs: [
                    "Wallpaper Exchange 是用户生成内容平台。我们不会预先筛查所有上传内容，也不对用户发布的内容负责。用户观点和内容不代表 Wallpaper Exchange。",
                ]),
                .init(id: "12", heading: "变更", paragraphs: [
                    "我们可能随时修订这些条款。变更发布后生效。变更后继续使用本服务，即表示你接受更新后的条款。",
                ]),
                .init(id: "13", heading: "终止", paragraphs: [
                    "如果我们认为你的行为违反本条款或损害其他用户或本服务，我们可以随时暂停或终止你的访问权限，且无需提前通知。",
                ]),
                .init(id: "14", heading: "适用法律", paragraphs: [
                    "本条款应依据适用法律解释和执行，不适用冲突法原则。任何争议应提交有管辖权的法院解决。",
                ]),
                .init(id: "15", heading: "联系方式", paragraphs: [
                    "如对本条款有疑问，请通过 support@wallpaperexchange.com 联系我们。",
                ]),
            ])
        case .zhHant:
            return LegalDoc(title: title, updated: "2026 年 5 月 8 日", version: "v1.0", sections: [
                .init(id: "01", heading: "接受條款", paragraphs: [
                    "存取或使用由 wallpaperexchange.com 提供的 Wallpaper Exchange 服務，即表示你同意受本服務條款約束。如果你不同意這些條款，請不要使用本服務。",
                ]),
                .init(id: "02", heading: "服務說明", paragraphs: [
                    "Wallpaper Exchange 是一個由社群驅動的平台，允許註冊使用者上傳、分享、探索和下載桌布。本服務使用金幣交換機制，使用者透過上傳桌布獲得金幣，並使用金幣下載其他使用者上傳的桌布。",
                ]),
                .init(id: "03", heading: "帳戶", paragraphs: [
                    "建立帳戶時，你必須提供準確資訊。",
                    "你需要自行負責帳戶憑證的安全。",
                    "你必須年滿 13 歲才能使用本服務。",
                    "同一自然人不得維護多個帳戶。",
                    "我們保留暫停或終止違反本條款帳戶的權利。",
                ]),
                .init(id: "04", heading: "你的內容", paragraphs: [
                    "你保留所上傳內容的所有權。上傳內容即表示你授予 Wallpaper Exchange 一項非獨占、全球範圍、免權利金的授權，用於託管、展示、分發並製作縮圖、裝置適配版本等衍生內容，以便營運本服務。",
                    "你聲明並保證你擁有上傳該內容所需的權利，且該內容不會侵犯任何第三方的智慧財產權、隱私權或其他權利。",
                    "你不得上傳違法、猥褻、誹謗、威脅或其他不適當內容。我們可自行決定移除任何內容，且無需提前通知。",
                ]),
                .init(id: "05", heading: "版權與 DMCA", paragraphs: [
                    "我們尊重智慧財產權。如果你認為 Wallpaper Exchange 上的內容侵犯了你的版權，請向我們提供作品說明、侵權材料及其位置、你的聯絡方式、善意聲明，以及在偽證責任下確認資訊準確的聲明。",
                    "DMCA 通知請寄至 dmca@wallpaperexchange.com。",
                ]),
                .init(id: "06", heading: "金幣系統", paragraphs: [
                    "金幣是僅可在本服務內使用的虛擬積分，不具有貨幣價值。金幣不可購買、出售、轉讓或兌換為真實貨幣。",
                    "我們可隨時調整金幣價值、獲得規則或消耗規則。濫用金幣系統可能導致帳戶被暫停。",
                ]),
                .init(id: "07", heading: "禁止行為", paragraphs: [
                    "你不得上傳無權分享的內容，不得使用自動化工具擷取或操作本服務，不得規避金幣系統，不得將下載的桌布在競爭平台上用於商業再分發，不得騷擾其他使用者，也不得干擾本服務的正常運作。",
                ]),
                .init(id: "08", heading: "免責聲明", paragraphs: [
                    "本服務按「現狀」和「可用」提供，不作任何明示或默示保證，包括但不限於適售性、特定用途適用性和不侵權保證。",
                ]),
                .init(id: "09", heading: "責任限制", paragraphs: [
                    "在法律允許的最大範圍內，Wallpaper Exchange 及其營運方不對任何間接、附帶、特殊、後果性或懲罰性損害負責。我們的總責任不超過你在索賠前十二個月向我們支付的金額，或 100 美元，以較低者為準。",
                ]),
                .init(id: "10", heading: "賠償", paragraphs: [
                    "對於因你使用本服務、上傳內容或違反本條款而引起的任何索賠、損害、損失或費用，你同意賠償並使 Wallpaper Exchange、其營運方、關聯方和貢獻者免受損害。",
                ]),
                .init(id: "11", heading: "內容責任", paragraphs: [
                    "Wallpaper Exchange 是使用者生成內容平台。我們不會預先篩查所有上傳內容，也不對使用者發布的內容負責。使用者觀點和內容不代表 Wallpaper Exchange。",
                ]),
                .init(id: "12", heading: "變更", paragraphs: [
                    "我們可能隨時修訂這些條款。變更發布後生效。變更後繼續使用本服務，即表示你接受更新後的條款。",
                ]),
                .init(id: "13", heading: "終止", paragraphs: [
                    "如果我們認為你的行為違反本條款或損害其他使用者或本服務，我們可以隨時暫停或終止你的存取權限，且無需提前通知。",
                ]),
                .init(id: "14", heading: "適用法律", paragraphs: [
                    "本條款應依據適用法律解釋和執行，不適用衝突法原則。任何爭議應提交有管轄權的法院解決。",
                ]),
                .init(id: "15", heading: "聯絡方式", paragraphs: [
                    "如對本條款有疑問，請透過 support@wallpaperexchange.com 聯絡我們。",
                ]),
            ])
        case .ja:
            return LegalDoc(title: title, updated: "2026年5月8日", version: "v1.0", sections: [
                .init(id: "01", heading: "同意", paragraphs: [
                    "wallpaperexchange.com で提供される Wallpaper Exchange サービスにアクセスまたは利用することで、本利用規約に同意したものとみなされます。同意しない場合は、本サービスを利用しないでください。",
                ]),
                .init(id: "02", heading: "サービス", paragraphs: [
                    "Wallpaper Exchange は、登録ユーザーが壁紙をアップロード、共有、発見、ダウンロードできるコミュニティ主導のプラットフォームです。本サービスはコイン交換システムを採用し、ユーザーは壁紙のアップロードでコインを獲得し、他のユーザーがアップロードした壁紙のダウンロードにコインを使用します。",
                ]),
                .init(id: "03", heading: "アカウント", paragraphs: [
                    "アカウント作成時には正確な情報を提供する必要があります。",
                    "アカウント認証情報の安全管理はユーザー自身の責任です。",
                    "本サービスを利用するには 13 歳以上である必要があります。",
                    "同一人物が複数のアカウントを維持することはできません。",
                    "本規約に違反したアカウントを停止または終了する権利を当社は留保します。",
                ]),
                .init(id: "04", heading: "あなたのコンテンツ", paragraphs: [
                    "アップロードしたコンテンツの所有権はあなたに残ります。アップロードすることで、Wallpaper Exchange に対し、本サービスの運営目的でコンテンツをホスト、表示、配布し、サムネイルやデバイス別バリエーションなどの派生物を作成するための、非独占的、全世界的、ロイヤリティフリーのライセンスを付与します。",
                    "あなたは、当該コンテンツをアップロードするために必要な権利を有し、第三者の知的財産権、プライバシー権、その他の権利を侵害しないことを表明し保証します。",
                    "違法、わいせつ、名誉毀損、脅迫的、またはその他不適切なコンテンツをアップロードしてはなりません。当社は独自の判断で、事前通知なくコンテンツを削除できます。",
                ]),
                .init(id: "05", heading: "著作権と DMCA", paragraphs: [
                    "当社は知的財産権を尊重します。Wallpaper Exchange 上のコンテンツがあなたの著作権を侵害していると考える場合は、対象作品、侵害素材とその場所、連絡先情報、善意に基づく声明、および情報が正確であることを偽証罪の制裁の下で示す声明を添えてご連絡ください。",
                    "DMCA 通知は dmca@wallpaperexchange.com へ送信してください。",
                ]),
                .init(id: "06", heading: "コインシステム", paragraphs: [
                    "コインは本サービス内でのみ使用できる仮想クレジットであり、金銭的価値はありません。コインを購入、販売、譲渡、または現実の通貨と交換することはできません。",
                    "当社はコインの価値、獲得率、使用率をいつでも変更できます。コインシステムの不正利用はアカウント停止につながる場合があります。",
                ]),
                .init(id: "07", heading: "禁止行為", paragraphs: [
                    "共有する権利のないコンテンツのアップロード、自動化ツールによるスクレイピングや操作、コインシステムの回避、競合プラットフォームでの商用再配布、他ユーザーへの嫌がらせ、本サービスの正常な運営を妨げる行為は禁止されています。",
                ]),
                .init(id: "08", heading: "免責", paragraphs: [
                    "本サービスは「現状有姿」かつ「提供可能な範囲」で提供され、商品性、特定目的適合性、非侵害性を含む、明示または黙示のいかなる保証も行いません。",
                ]),
                .init(id: "09", heading: "責任制限", paragraphs: [
                    "法律で認められる最大限の範囲で、Wallpaper Exchange およびその運営者は、間接的、付随的、特別、結果的、または懲罰的損害について責任を負いません。当社の総責任は、請求前 12 か月間にあなたが当社へ支払った金額、または 100 米ドルのいずれか低い方を上限とします。",
                ]),
                .init(id: "10", heading: "補償", paragraphs: [
                    "あなたは、本サービスの利用、アップロードしたコンテンツ、または本規約違反に起因する請求、損害、損失、費用について、Wallpaper Exchange、その運営者、関連会社、貢献者を補償し免責することに同意します。",
                ]),
                .init(id: "11", heading: "コンテンツ責任", paragraphs: [
                    "Wallpaper Exchange はユーザー生成コンテンツのプラットフォームです。当社はアップロードを事前審査せず、ユーザーが投稿したコンテンツについて責任を負いません。ユーザーの見解やコンテンツは Wallpaper Exchange を代表するものではありません。",
                ]),
                .init(id: "12", heading: "変更", paragraphs: [
                    "当社はいつでも本規約を改定できます。変更は掲載時に有効となります。変更後も本サービスを継続して利用することで、更新後の規約に同意したものとみなされます。",
                ]),
                .init(id: "13", heading: "終了", paragraphs: [
                    "あなたの行為が本規約に違反する、または他のユーザーや本サービスに有害であると当社が判断した場合、当社は事前通知なくいつでもアクセスを停止または終了できます。",
                ]),
                .init(id: "14", heading: "準拠法", paragraphs: [
                    "本規約は、抵触法の原則にかかわらず、適用される法律に従って解釈および執行されます。紛争は管轄権を有する裁判所で解決されます。",
                ]),
                .init(id: "15", heading: "連絡先", paragraphs: [
                    "本規約に関する質問は support@wallpaperexchange.com までお問い合わせください。",
                ]),
            ])
        case .en:
            return termsEnglish(title: title)
        }
    }

    static func privacy(title: String, language: AppLanguage) -> LegalDoc {
        switch language {
        case .zhHans, .system:
            return LegalDoc(title: title, updated: "2026 年 5 月 8 日", version: "v1.0", sections: [
                .init(id: "01", heading: "我们收集的信息", paragraphs: [
                    "账户信息：注册时，我们会收集你的用户名、邮箱地址和哈希处理后的密码。我们不会存储明文密码。",
                    "使用数据：我们会收集你与本服务互动的信息，包括上传、下载、喜欢、收藏和金币交易。",
                    "设备信息：使用原生客户端时，你的屏幕分辨率会发送到服务器，以便列表只返回适合当前设备的壁纸。该信息不会永久保存。",
                    "上传内容：你上传的壁纸会存储在我们的服务器上。分辨率、文件大小、主要颜色和文件类型等元数据会随图片一并提取和保存。",
                ]),
                .init(id: "02", heading: "我们如何使用信息", paragraphs: [
                    "我们使用数据来运营、维护和改进本服务，处理金币交易，生成设备适配壁纸版本，展示你的公开个人资料，发送重要更新，执行服务条款，并防止滥用。",
                ]),
                .init(id: "03", heading: "共享", paragraphs: [
                    "我们不会向第三方出售、交易或出租你的个人信息。",
                    "你上传的壁纸和公开个人资料会对所有用户可见。",
                    "在法律、法院命令或政府要求下，我们可能披露相关信息。",
                    "我们可能与帮助运营本服务的可信服务提供商共享数据，前提是其承担保密义务。",
                    "当有必要保护本服务、用户或公众的权利、安全或财产时，我们可能共享信息。",
                ]),
                .init(id: "04", heading: "存储与安全", paragraphs: [
                    "你的数据存储在受保护的服务器上。我们采取合理的技术和组织措施，包括加密密码存储、安全 HTTPS 连接和访问控制。但没有任何系统是绝对安全的。",
                ]),
                .init(id: "05", heading: "Cookie 与本地存储", paragraphs: [
                    "我们使用本地存储和会话存储来保持登录状态、记住偏好并缓存滚动位置。我们不使用第三方跟踪 Cookie。",
                ]),
                .init(id: "06", heading: "你的权利", paragraphs: [
                    "你可以访问我们持有的与你有关的个人数据。",
                    "你可以更正个人资料中的不准确信息。",
                    "你可以随时删除自己上传的壁纸。",
                    "你可以联系我们请求删除账户。账户删除后，除非法律要求保留，否则你的个人数据和上传内容会被永久删除。",
                ]),
                .init(id: "07", heading: "儿童", paragraphs: [
                    "本服务不面向 13 周岁以下儿童。我们不会有意收集 13 周岁以下儿童的个人信息。",
                ]),
                .init(id: "08", heading: "保留期限", paragraphs: [
                    "只要你的账户处于有效状态，我们会保留账户信息和上传内容。账户删除后，除非法律要求或合法业务目的需要，我们会在 30 天内删除你的个人数据。",
                ]),
                .init(id: "09", heading: "变更", paragraphs: [
                    "我们可能不时更新本隐私政策。重大变更会在页面上发布并更新最后更新日期。变更后继续使用本服务，即表示你接受更新后的政策。",
                ]),
                .init(id: "10", heading: "联系方式", paragraphs: [
                    "如对本隐私政策有疑问，或希望行使你的数据权利，请通过 privacy@wallpaperexchange.com 联系我们。",
                ]),
            ])
        case .zhHant:
            return LegalDoc(title: title, updated: "2026 年 5 月 8 日", version: "v1.0", sections: [
                .init(id: "01", heading: "我們收集的資訊", paragraphs: [
                    "帳戶資訊：註冊時，我們會收集你的使用者名稱、電子郵件地址和雜湊處理後的密碼。我們不會儲存明文密碼。",
                    "使用資料：我們會收集你與本服務互動的資訊，包括上傳、下載、喜歡、收藏和金幣交易。",
                    "裝置資訊：使用裝置匹配功能時，你的螢幕解析度會送至伺服器，以查找適合你裝置的桌布。該資訊不會永久保存。",
                    "上傳內容：你上傳的桌布會儲存在我們的伺服器上。解析度、檔案大小、主要顏色和檔案類型等中繼資料會隨圖片一併擷取和保存。",
                ]),
                .init(id: "02", heading: "我們如何使用資訊", paragraphs: [
                    "我們使用資料來營運、維護和改進本服務，處理金幣交易，生成裝置適配桌布版本，展示你的公開個人資料，發送重要更新，執行服務條款，並防止濫用。",
                ]),
                .init(id: "03", heading: "共享", paragraphs: [
                    "我們不會向第三方出售、交易或出租你的個人資訊。",
                    "你上傳的桌布和公開個人資料會對所有使用者可見。",
                    "在法律、法院命令或政府要求下，我們可能揭露相關資訊。",
                    "我們可能與協助營運本服務的可信服務提供商共享資料，前提是其承擔保密義務。",
                    "當有必要保護本服務、使用者或公眾的權利、安全或財產時，我們可能共享資訊。",
                ]),
                .init(id: "04", heading: "儲存與安全", paragraphs: [
                    "你的資料儲存在受保護的伺服器上。我們採取合理的技術和組織措施，包括加密密碼儲存、安全 HTTPS 連線和存取控制。但沒有任何系統是絕對安全的。",
                ]),
                .init(id: "05", heading: "Cookie 與本機儲存", paragraphs: [
                    "我們使用本機儲存和工作階段儲存來保持登入狀態、記住偏好並快取捲動位置。我們不使用第三方追蹤 Cookie。",
                ]),
                .init(id: "06", heading: "你的權利", paragraphs: [
                    "你可以存取我們持有的與你有關的個人資料。",
                    "你可以更正個人資料中的不準確資訊。",
                    "你可以隨時刪除自己上傳的桌布。",
                    "你可以聯絡我們請求刪除帳戶。帳戶刪除後，除非法律要求保留，否則你的個人資料和上傳內容會被永久刪除。",
                ]),
                .init(id: "07", heading: "兒童", paragraphs: [
                    "本服務不面向 13 歲以下兒童。我們不會有意收集 13 歲以下兒童的個人資訊。",
                ]),
                .init(id: "08", heading: "保留期限", paragraphs: [
                    "只要你的帳戶處於有效狀態，我們會保留帳戶資訊和上傳內容。帳戶刪除後，除非法律要求或合法業務目的需要，我們會在 30 天內刪除你的個人資料。",
                ]),
                .init(id: "09", heading: "變更", paragraphs: [
                    "我們可能不時更新本隱私政策。重大變更會在頁面上發布並更新最後更新日期。變更後繼續使用本服務，即表示你接受更新後的政策。",
                ]),
                .init(id: "10", heading: "聯絡方式", paragraphs: [
                    "如對本隱私政策有疑問，或希望行使你的資料權利，請透過 privacy@wallpaperexchange.com 聯絡我們。",
                ]),
            ])
        case .ja:
            return LegalDoc(title: title, updated: "2026年5月8日", version: "v1.0", sections: [
                .init(id: "01", heading: "収集する情報", paragraphs: [
                    "アカウント情報：登録時に、ユーザー名、メールアドレス、ハッシュ化されたパスワードを収集します。平文のパスワードは保存しません。",
                    "利用データ：アップロード、ダウンロード、いいね、お気に入り、コイン取引など、本サービスとのやり取りに関する情報を収集します。",
                    "デバイス情報：デバイスマッチング機能を使用する際、あなたの画面解像度がサーバーに送信され、デバイスに合う壁紙を探すために使われます。この情報は恒久的には保存されません。",
                    "アップロードされたコンテンツ：アップロードした壁紙は当社サーバーに保存されます。解像度、ファイルサイズ、主要色、ファイル形式などのメタデータも画像とともに抽出、保存されます。",
                ]),
                .init(id: "02", heading: "利用目的", paragraphs: [
                    "当社は、サービスの運営、維持、改善、コイン取引の処理、デバイス別壁紙バリエーションの生成、公開プロフィールの表示、重要なお知らせの送信、利用規約の執行、不正利用の防止のためにデータを使用します。",
                ]),
                .init(id: "03", heading: "共有", paragraphs: [
                    "当社は個人情報を第三者に販売、取引、貸与しません。",
                    "アップロードした壁紙と公開プロフィールはすべてのユーザーに表示されます。",
                    "法律、裁判所命令、政府機関の要請により必要な場合、情報を開示することがあります。",
                    "本サービスの運営を支援する信頼できるサービス提供者と、守秘義務の下でデータを共有することがあります。",
                    "本サービス、ユーザー、または公衆の権利、安全、財産を保護するために必要な場合、情報を共有することがあります。",
                ]),
                .init(id: "04", heading: "保存とセキュリティ", paragraphs: [
                    "データは保護されたサーバーに保存されます。当社は暗号化されたパスワード保存、安全な HTTPS 接続、アクセス制御など、合理的な技術的および組織的対策を講じます。ただし、完全に安全なシステムはありません。",
                ]),
                .init(id: "05", heading: "Cookie とローカルストレージ", paragraphs: [
                    "ログイン状態の維持、設定の記憶、スクロール位置のキャッシュのために、ローカルストレージとセッションストレージを使用します。第三者追跡 Cookie は使用しません。",
                ]),
                .init(id: "06", heading: "あなたの権利", paragraphs: [
                    "当社が保持するあなたの個人データへアクセスできます。",
                    "プロフィール内の不正確な情報を修正できます。",
                    "アップロードした壁紙はいつでも削除できます。",
                    "当社に連絡してアカウント削除を依頼できます。削除後、法的に保持が必要な場合を除き、個人データとアップロードコンテンツは完全に削除されます。",
                ]),
                .init(id: "07", heading: "児童", paragraphs: [
                    "本サービスは 13 歳未満の児童を対象としていません。当社は 13 歳未満の児童から個人情報を故意に収集しません。",
                ]),
                .init(id: "08", heading: "保持期間", paragraphs: [
                    "アカウントが有効である限り、アカウント情報とアップロードコンテンツを保持します。アカウント削除後は、法的要件または正当な業務目的で必要な場合を除き、30 日以内に個人データを削除します。",
                ]),
                .init(id: "09", heading: "変更", paragraphs: [
                    "当社は本プライバシーポリシーを随時更新することがあります。重要な変更は、更新された最終更新日とともに掲載されます。変更後も本サービスを継続して利用することで、更新後のポリシーに同意したものとみなされます。",
                ]),
                .init(id: "10", heading: "連絡先", paragraphs: [
                    "本プライバシーポリシーに関する質問、またはデータ権利の行使を希望する場合は privacy@wallpaperexchange.com までお問い合わせください。",
                ]),
            ])
        case .en:
            return privacyEnglish(title: title)
        }
    }

    static func dmca(title: String, language: AppLanguage) -> LegalDoc {
        switch language {
        case .zhHans, .system:
            return LegalDoc(title: title, updated: "2026-05-14", version: "v1.0", sections: [
                .init(id: "01", heading: "概述", paragraphs: [
                    "Wallpaper Exchange 是用户驱动的目录，任何拥有账户的人都可以上传壁纸。我们尊重知识产权，并依据美国《数字千年版权法案》（DMCA）及同等本地框架处理可信的版权主张。",
                    "如果你认为本站材料侵犯了你的版权，请发送完整通知。收到完整通知后，我们通常会在 3 个工作日内移除或限制访问明显侵权的材料。",
                ]),
                .init(id: "02", heading: "通知发送地址", paragraphs: [
                    "指定版权代理：copyright@wallpaperexchange.com",
                ]),
                .init(id: "03", heading: "通知应包含", paragraphs: [
                    "你主张被侵权作品的识别信息。",
                    "你要求我们移除的 Wallpaper Exchange 上具体壁纸的 URL。",
                    "你的联系方式，包括邮箱和实体地址。",
                    "你基于善意认为该使用未经版权人、其代理人或法律授权的声明。",
                    "在伪证责任下确认通知信息准确，且你是版权人或获授权代表版权人行事的声明。",
                    "你的实体或电子签名。",
                ]),
                .init(id: "04", heading: "反通知", paragraphs: [
                    "如果你上传的壁纸被移除，并且你认为这是错误或误识别，请向同一地址发送反通知，包含被移除材料的识别信息、你的联系方式、在伪证责任下确认移除属于错误或误识别的声明，以及你同意接受当地法院管辖的声明。",
                ]),
                .init(id: "05", heading: "重复侵权者", paragraphs: [
                    "收到多次经证实版权主张的账户将被终止。",
                ]),
                .init(id: "06", heading: "应用内举报", paragraphs: [
                    "对于非版权问题的其他内容疑虑，请使用壁纸详情页的举报按钮。这些举报会进入同一个审核队列，但会依据社区准则而非版权法处理。",
                ]),
            ])
        case .zhHant:
            return LegalDoc(title: title, updated: "2026-05-14", version: "v1.0", sections: [
                .init(id: "01", heading: "概述", paragraphs: [
                    "Wallpaper Exchange 是使用者驅動的目錄，任何擁有帳戶的人都可以上傳桌布。我們尊重智慧財產權，並依據美國《數位千禧年著作權法》（DMCA）及同等本地框架處理可信的版權主張。",
                    "如果你認為本站材料侵犯了你的版權，請寄送完整通知。收到完整通知後，我們通常會在 3 個工作日內移除或限制存取明顯侵權的材料。",
                ]),
                .init(id: "02", heading: "通知寄送地址", paragraphs: [
                    "指定版權代理：copyright@wallpaperexchange.com",
                ]),
                .init(id: "03", heading: "通知應包含", paragraphs: [
                    "你主張被侵權作品的識別資訊。",
                    "你要求我們移除的 Wallpaper Exchange 上具體桌布的 URL。",
                    "你的聯絡方式，包括電子郵件和實體地址。",
                    "你基於善意認為該使用未經版權人、其代理人或法律授權的聲明。",
                    "在偽證責任下確認通知資訊準確，且你是版權人或獲授權代表版權人行事的聲明。",
                    "你的實體或電子簽名。",
                ]),
                .init(id: "04", heading: "反通知", paragraphs: [
                    "如果你上傳的桌布被移除，並且你認為這是錯誤或誤識別，請向同一地址寄送反通知，包含被移除材料的識別資訊、你的聯絡方式、在偽證責任下確認移除屬於錯誤或誤識別的聲明，以及你同意接受當地法院管轄的聲明。",
                ]),
                .init(id: "05", heading: "重複侵權者", paragraphs: [
                    "收到多次經證實版權主張的帳戶將被終止。",
                ]),
                .init(id: "06", heading: "應用程式內檢舉", paragraphs: [
                    "對於非版權問題的其他內容疑慮，請使用桌布詳情頁的檢舉按鈕。這些檢舉會進入同一個審核佇列，但會依據社群準則而非版權法處理。",
                ]),
            ])
        case .ja:
            return LegalDoc(title: title, updated: "2026-05-14", version: "v1.0", sections: [
                .init(id: "01", heading: "概要", paragraphs: [
                    "Wallpaper Exchange はユーザー主導のカタログであり、アカウントを持つ誰もが壁紙をアップロードできます。当社は知的財産権を尊重し、米国デジタルミレニアム著作権法（DMCA）および同等の地域的枠組みに基づき、信頼できる著作権請求に対応します。",
                    "本サイト上の素材があなたの著作権を侵害していると考える場合は、完全な通知を送付してください。完全な通知を受け取った場合、明らかに侵害している素材については通常 3 営業日以内に削除またはアクセス制限を行います。",
                ]),
                .init(id: "02", heading: "通知の送付先", paragraphs: [
                    "指定著作権代理人：copyright@wallpaperexchange.com",
                ]),
                .init(id: "03", heading: "通知に含める内容", paragraphs: [
                    "侵害されたと主張する著作物の識別情報。",
                    "削除を求める Wallpaper Exchange 上の具体的な壁紙 URL。",
                    "メールアドレスと住所を含む連絡先情報。",
                    "当該利用が著作権者、その代理人、または法律によって許可されていないと善意で信じる旨の声明。",
                    "通知の情報が正確であり、あなたが著作権者または著作権者の代理として行動する権限を持つことを、偽証罪の制裁の下で示す声明。",
                    "あなたの物理的または電子的な署名。",
                ]),
                .init(id: "04", heading: "異議申し立て通知", paragraphs: [
                    "あなたがアップロードした壁紙が削除され、それが誤りまたは誤認であると考える場合は、同じ宛先へ異議申し立て通知を送付してください。削除された素材の識別情報、連絡先情報、削除が誤りまたは誤認であったことを偽証罪の制裁の下で示す声明、および地域裁判所の管轄に同意する旨を含めてください。",
                ]),
                .init(id: "05", heading: "反復侵害者", paragraphs: [
                    "複数回の実証された著作権請求を受けたアカウントは終了されます。",
                ]),
                .init(id: "06", heading: "アプリ内報告", paragraphs: [
                    "著作権以外のコンテンツ上の懸念については、壁紙詳細ページの報告ボタンを使用してください。これらの報告は同じモデレーションキューに送られますが、著作権法ではなくコミュニティガイドラインに基づいて処理されます。",
                ]),
            ])
        case .en:
            return dmcaEnglish(title: title)
        }
    }

    private static func termsEnglish(title: String) -> LegalDoc {
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

    private static func privacyEnglish(title: String) -> LegalDoc {
        LegalDoc(
            title: title,
            updated: "May 8, 2026",
            version: "v1.0",
            sections: [
                .init(id: "01", heading: "What we collect", paragraphs: [
                    "Account information: when you register, we collect your username, email address, and a hashed version of your password. We do not store plain-text passwords.",
                    "Usage data: we collect information about how you interact with the Service, including uploads, downloads, likes, favorites, and coin transactions.",
                    "Device information: when you use a native client, your screen resolution is sent to the server so lists only return wallpapers that fit your current device. This information is not stored permanently.",
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

    private static func dmcaEnglish(title: String) -> LegalDoc {
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
