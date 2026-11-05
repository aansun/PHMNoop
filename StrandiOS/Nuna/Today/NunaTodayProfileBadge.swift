#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// The wearer's picture: the photo they chose, else their initials in black on the warm gradient.
struct NunaProfileAvatar: View {
    @EnvironmentObject private var profile: ProfileStore
    let size: CGFloat

    private var initials: String {
        String(profile.displayName.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }

    var body: some View {
        Group {
            if profile.hasAvatar {
                ProfileAvatarView(imageData: profile.avatarImageData, size: size)
            } else {
                Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.38, blue: 0.35), Color(red: 1, green: 0.52, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size, height: size)
                    .overlay {
                        if initials.isEmpty { Image(systemName: "person.fill").font(.system(size: size * 0.41)).foregroundStyle(.black.opacity(0.75)) }
                        else { Text(verbatim: initials).font(.nuna(size: size * 0.41, weight: .heavy)).tracking(0).foregroundStyle(.black) }
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Top left of Today: the picture, which opens the profile, and the day streak under its edge, which opens the streak page. A red dot on the picture
/// says there are unread updates (their inbox lives on the profile page).
struct NunaTodayProfileBadge: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var updateStore: UpdateStore
    @Environment(\.nunaPushMe) private var pushMe
    private static let avatar: CGFloat = 32

    var body: some View {
        let streak = NunaStreak.compute(days: repo.days).current
        ZStack(alignment: .leading) {
            Button { pushMe(.dayStreak) } label: {
                HStack(spacing: 10) {
                    NunaFlameIcon(height: 20)
                    // DIN Medium at 13 pt: the number is a quiet label beside the flame, not a figure to read at a glance.
                    Text(verbatim: "\(streak)").font(.nuna(size: 13, weight: .medium, design: NunaType.design)).tracking(0).foregroundStyle(NunaPalette.textPrimary)
                }
                .padding(.leading, 19).padding(.trailing, 16).frame(height: 32)
                .background(NunaPalette.textPrimary.opacity(0.1), in: Capsule())
                .padding(.leading, Self.avatar - 12).frame(height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Day streak")).accessibilityValue(Text(verbatim: "\(streak)"))
            Button { pushMe(.profile) } label: {
                NunaProfileAvatar(size: Self.avatar)
                    .overlay(alignment: .topTrailing) {
                        if updateStore.unreadCount > 0 { Circle().fill(NunaPalette.alert).frame(width: 10, height: 10).overlay(Circle().strokeBorder(NunaPalette.canvas, lineWidth: 1.5)).offset(x: 2, y: -2) }
                    }
                    .frame(width: 44, height: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Profile"))
        }
        .padding(.leading, 8)
    }
}
#endif
