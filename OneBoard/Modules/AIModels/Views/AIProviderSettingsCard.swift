import SwiftUI

struct AIProviderSettingsCard: View {
    let profile: AIProviderProfile
    let active: Bool
    let switching: Bool
    let snapshot: AIQuotaSnapshot?
    let error: String?
    let today: AITokenTotals?
    let total: AITokenTotals?
    let officialQuota: AIProviderQuotaPresentation
    let onSwitch: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var usesServer: Bool { snapshot?.totalTokens != nil }

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: profile.kind == .official ? "building.columns" : "square.stack.3d.up")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(profile.kind == .official ? SettingsPalette.accent : SettingsPalette.teal)
                        .frame(width: 44, height: 44)
                        .background((profile.kind == .official ? SettingsPalette.accent : SettingsPalette.teal).opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(profile.title).font(.system(size: 15, weight: .semibold))
                            if active {
                                Label("使用中", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(SettingsPalette.teal)
                                    .padding(.horizontal, 7).padding(.vertical, 4)
                                    .background(SettingsPalette.teal.opacity(0.08), in: Capsule())
                            }
                        }
                        Text(profile.model).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            .lineLimit(1).help(profile.model)
                        if let note = profile.note {
                            Text(note).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 6)
                    if !active {
                        Button("切换", action: onSwitch).buttonStyle(SettingsActionStyle())
                            .disabled(switching)
                    }
                    Button(action: onEdit) { Image(systemName: "slider.horizontal.3") }
                        .buttonStyle(SettingsActionStyle()).help("编辑供应商").accessibilityLabel("编辑 \(profile.title)")
                    Menu {
                        Button("删除供应商", role: .destructive, action: onDelete)
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize().frame(width: 20, height: 30)
                        .help("更多操作").accessibilityLabel("\(profile.title) 更多操作")
                }
                if profile.kind == .official {
                    Label(officialQuota.text, systemImage: "chart.pie")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(officialQuota.tone == .normal ? SettingsPalette.teal : .secondary)
                        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                        .background(SettingsPalette.accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    HStack {
                        Label(snapshot?.balance ?? "额度尚未同步", systemImage: "creditcard")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(snapshot == nil ? .secondary : SettingsPalette.ink)
                        Spacer()
                        if let snapshot {
                            Text(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened) + " 更新")
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                                .help(snapshot.fetchedAt.formatted(date: .complete, time: .standard))
                        }
                    }
                    HStack(spacing: 0) {
                        metric("当日 Token", value: usesServer ? currentServerTokens : today?.total)
                        Divider().padding(.vertical, 12)
                        metric("累计 Token", value: usesServer ? snapshot?.totalTokens : total?.total)
                        Divider().padding(.vertical, 12)
                        metric("累计缓存命中", value: usesServer ? snapshot?.totalCacheTokens : total?.cacheRead)
                    }
                    .frame(height: 78)
                    .background(SettingsPalette.accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 7) {
                            if usesServer {
                                Text("供应商当日缓存命中：\(snapshot?.todayCacheTokens.map { $0.formatted() } ?? "—") Token")
                            }
                            if let today, let total {
                                Text("OneBoard 当日 \(today.total.formatted()) · 累计 \(total.total.formatted()) Token")
                                Text("当日：输入 \(today.input.formatted()) · 输出 \(today.output.formatted()) · 缓存命中 \(today.cacheRead.formatted()) · 缓存写入 \(today.cacheCreation.formatted())")
                                Text("累计：输入 \(total.input.formatted()) · 输出 \(total.output.formatted()) · 缓存命中 \(total.cacheRead.formatted()) · 缓存写入 \(total.cacheCreation.formatted())")
                            }
                            Text("总量包含缓存命中和写入，不重复相加。供应商统计采用服务端时区；OneBoard 仅统计启用后的本机代理和翻译请求，两者不合计。")
                                .lineSpacing(3)
                        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
                    } label: {
                        HStack {
                            Text(usesServer ? "供应商统计 · 明细与来源" : "OneBoard 统计 · 明细与来源")
                            Spacer()
                            Text(URLComponents(string: profile.baseURL)?.host ?? profile.baseURL)
                                .lineLimit(1).truncationMode(.middle).help(profile.baseURL)
                        }.font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }.padding(20)
        }
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(active ? SettingsPalette.accent.opacity(0.28) : .clear, lineWidth: 1))
    }

    private var currentServerTokens: Int64? {
        guard let snapshot, Calendar.current.isDateInToday(snapshot.fetchedAt) else { return nil }
        return snapshot.todayTokens
    }

    private func metric(_ title: String, value: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text(value.map { $0.formatted() } ?? "—")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
    }
}
