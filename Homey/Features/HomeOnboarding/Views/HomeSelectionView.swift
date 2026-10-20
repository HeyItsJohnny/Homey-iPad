import SwiftUI

struct HomeSelectionView: View {
    @EnvironmentObject private var homeService: HomeService
    @AppStorage("selectedHomeID") private var storedSelectedHomeID = ""

    var restoresStoredSelectionOnAppear = true
    var onHomeSelected: () -> Void = {}

    @State private var switchingHomeID: UUID?

    private var selectedHome: HomeSummary? {
        homeService.selectedHome()
    }

    private var hasOneHome: Bool {
        homeService.homes.count == 1
    }

    var body: some View {
        ZStack {
            HomeyTheme.backgroundPrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    if homeService.homes.isEmpty {
                        emptyState
                    } else {
                        currentHomeSection
                        homesSection
                        secondaryActionsSection
                    }
                }
                .padding(.horizontal, 34)
                .padding(.top, 34)
                .padding(.bottom, 38)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if restoresStoredSelectionOnAppear {
                homeService.restoreSelectedHome(from: storedSelectedHomeID)
            }
        }
        .onChange(of: homeService.selectedHomeID) { _, selectedHomeID in
            storedSelectedHomeID = selectedHomeID?.uuidString ?? ""
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Change Home")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("Choose which home you want to view and manage.")
                    .font(.title3)
                    .foregroundStyle(HomeyTheme.textSecondary)
            }

            Spacer()

            Button {
                onHomeSelected()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyTheme.primary)
                .frame(minHeight: 44)
                .padding(.horizontal, 16)
                .background(HomeyTheme.surfacePrimary, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(HomeyTheme.borderSubtle, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentHomeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Current Home",
                subtitle: "The home currently shown on your dashboard."
            )

            if let selectedHome {
                ChangeHomeCard(
                    home: selectedHome,
                    isCurrent: true,
                    isSwitching: switchingHomeID == selectedHome.id,
                    action: {}
                )
                .disabled(true)
                .accessibilityLabel("Current home, \(selectedHome.name)")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No Home Selected")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(HomeyTheme.textPrimary)

                    Text("Choose a home below to continue.")
                        .font(.subheadline)
                        .foregroundStyle(HomeyTheme.textSecondary)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dashboardCard(cornerRadius: HomeyRadius.page)
            }
        }
    }

    private var homesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Your Homes",
                subtitle: "Select a home to switch your dashboard."
            )

            VStack(spacing: 12) {
                ForEach(homeService.homes) { home in
                    let isCurrent = home.id == homeService.selectedHomeID

                    ChangeHomeCard(
                        home: home,
                        isCurrent: isCurrent,
                        isSwitching: switchingHomeID == home.id
                    ) {
                        select(home)
                    }
                    .disabled(isCurrent || switchingHomeID != nil)
                    .accessibilityLabel(isCurrent ? "Current home, \(home.name)" : "Switch to \(home.name)")
                }

                if hasOneHome {
                    Text("You currently belong to one home.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(HomeyTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "house")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(HomeyTheme.primary)

            Text("No Homes Available")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyTheme.textPrimary)

            Text("Create or join a home to get started.")
                .font(.body)
                .foregroundStyle(HomeyTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(34)
        .frame(maxWidth: .infinity, minHeight: 260)
        .dashboardCard(cornerRadius: HomeyRadius.page)
    }

    private var secondaryActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "More Options",
                subtitle: "Add another home when your family needs a separate space."
            )

            NavigationLink {
                CreateHomeView()
            } label: {
                HStack(spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                            .fill(HomeyTheme.primary.opacity(0.12))
                            .frame(width: 44, height: 44)

                        Image(systemName: "plus")
                            .font(.body.weight(.bold))
                            .foregroundStyle(HomeyTheme.primary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Create Another Home")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HomeyTheme.textPrimary)

                        Text("Start a separate household space.")
                            .font(.caption)
                            .foregroundStyle(HomeyTheme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyTheme.textSecondary.opacity(0.7))
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dashboardCard(cornerRadius: HomeyRadius.page)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func select(_ home: HomeSummary) {
        guard switchingHomeID == nil else {
            return
        }

        guard home.id != homeService.selectedHomeID else {
            return
        }

        switchingHomeID = home.id

        storedSelectedHomeID = home.id.uuidString
        homeService.selectHome(id: home.id)
        switchingHomeID = nil
        onHomeSelected()
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyTheme.textPrimary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(HomeyTheme.textSecondary)
        }
    }
}

private struct ChangeHomeCard: View {
    let home: HomeSummary
    let isCurrent: Bool
    let isSwitching: Bool
    let action: () -> Void

    private var memberText: String {
        "\(home.memberCount) \(home.memberCount == 1 ? "Member" : "Members")"
    }

    private var timezoneText: String? {
        home.timezone
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                homeIcon

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 9) {
                        Text(home.name)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(HomeyTheme.textPrimary)
                            .lineLimit(1)

                        if isCurrent {
                            Text("Current")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(HomeyTheme.primary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(HomeyTheme.primarySoft, in: Capsule())
                        }
                    }

                    HStack(spacing: 8) {
                        Text(memberText)

                        if let timezoneText, !timezoneText.isEmpty {
                            Text("•")
                            Text(timezoneText)
                                .lineLimit(1)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(HomeyTheme.textSecondary)
                }

                Spacer(minLength: 18)

                trailingIndicator
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(
                isCurrent ? HomeyTheme.primarySoft.opacity(0.72) : HomeyTheme.surfacePrimary,
                in: RoundedRectangle(cornerRadius: HomeyRadius.page, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: HomeyRadius.page, style: .continuous)
                    .stroke(isCurrent ? HomeyTheme.primary.opacity(0.22) : HomeyTheme.borderSubtle, lineWidth: 1)
            }
            .shadow(color: HomeyTheme.shadow, radius: 14, x: 0, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: HomeyRadius.page, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var homeIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                .fill(HomeyTheme.borderSubtle.opacity(isCurrent ? 0.90 : 0.70))
                .frame(width: 52, height: 52)

            Image(systemName: "house.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(HomeyTheme.primary)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var trailingIndicator: some View {
        if isSwitching {
            ProgressView()
                .tint(HomeyTheme.primary)
                .accessibilityLabel("Switching Home")
        } else if isCurrent {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(HomeyTheme.primary)
                .accessibilityLabel("Selected")
        } else {
            Image(systemName: "chevron.right")
                .font(.body.weight(.bold))
                .foregroundStyle(HomeyTheme.textSecondary.opacity(0.7))
                .accessibilityHidden(true)
        }
    }
}

#Preview("Change Home") {
    NavigationStack {
        HomeSelectionView(restoresStoredSelectionOnAppear: false)
            .environmentObject(HomeService())
    }
}
