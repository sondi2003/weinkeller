import CloudKit
import CoreData
import SwiftUI

/// Abschnitt „Teilen“ in den Einstellungen: Keller für eine zweite Person freigeben,
/// Teilnehmer sehen, Freigabe verwalten.
struct CellarSharingSection: View {

    @Environment(\.managedObjectContext) private var context

    @State private var share: CKShare?
    @State private var cloudContainer: CKContainer?
    @State private var isPreparing = false
    @State private var isShowingSharingSheet = false
    @State private var errorMessage: String?
    /// Ist der Keller von jemand anderem geteilt worden, gibt es hier nichts zu verwalten.
    @State private var isGuest = false

    /// Eingeladene Personen ohne den Eigentümer. Zählt auch Einladungen, die noch offen sind.
    private var participants: [CKShare.Participant] {
        (share?.participants ?? []).filter { $0.role != .owner }
    }

    /// Eine angelegte, aber nie verschickte Freigabe gilt noch nicht als geteilt.
    private var isActuallyShared: Bool { !participants.isEmpty }

    var body: some View {
        Section {
            if isGuest {
                Label {
                    Text("Dieser Keller wurde mit dir geteilt. Verwalten kann ihn nur die Person, die ihn freigegeben hat.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(Color.accentColor)
                }
            } else if isActuallyShared {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keller ist freigegeben")
                            .font(.body.weight(.semibold))
                        Text(participants.count == 1
                             ? "1 weitere Person hat Zugriff."
                             : "\(participants.count) weitere Personen haben Zugriff.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)

                Button {
                    self.cloudContainer = CKContainer(identifier: PersistenceController.cloudContainerIdentifier)
                    isShowingSharingSheet = true
                } label: {
                    Label("Freigabe verwalten", systemImage: "person.crop.circle.badge.checkmark")
                }
            } else {
                Button {
                    Task { await prepareShare() }
                } label: {
                    HStack {
                        Label("Weinkeller teilen", systemImage: "square.and.arrow.up")
                        if isPreparing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isPreparing)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Teilen")
        } footer: {
            if isGuest {
                Text("Änderungen am Bestand sehen beide Seiten.")
            } else {
                Text("Lade eine Person mit eigener Apple-ID ein. Beide sehen denselben Bestand, auch wenn eine Flasche abgebucht wird.")
            }
        }
        .sheet(isPresented: $isShowingSharingSheet) {
            if let share, let cloudContainer {
                CloudSharingView(share: share, container: cloudContainer, title: "Weinkeller")
                    .ignoresSafeArea()
            }
        }
        .task { refresh() }
        .onChange(of: isShowingSharingSheet) { _, isShowing in
            // Nach dem Schliessen kann sich die Teilnehmerliste geändert haben.
            if !isShowing { refresh() }
        }
    }

    // MARK: Aktionen

    private func refresh() {
        let cellar = Cellar.findOrCreateDefault(in: context)
        isGuest = PersistenceController.shared.isSharedWithMe(cellar)
        share = PersistenceController.shared.existingShare(for: cellar)
    }

    /// Übersetzt die technischen CloudKit-Meldungen in etwas Lesbares.
    private static func friendlyMessage(for error: Error) -> String {
        let text = error.localizedDescription.lowercased()
        if let ckError = error as? CKError {
            switch ckError.code {
            case .notAuthenticated:
                return "Du bist auf diesem Gerät nicht in iCloud angemeldet. Melde dich in den Systemeinstellungen an und versuch es erneut."
            case .networkUnavailable, .networkFailure:
                return "Keine Verbindung zu iCloud. Bitte später erneut versuchen."
            case .quotaExceeded:
                return "Dein iCloud-Speicher ist voll."
            default:
                break
            }
        }
        if text.contains("ckaccountstatusnoaccount") || text.contains("without an icloud account") {
            return "Du bist auf diesem Gerät nicht in iCloud angemeldet. Melde dich in den Systemeinstellungen an und versuch es erneut."
        }
        if text.contains("network") {
            return "Keine Verbindung zu iCloud. Bitte später erneut versuchen."
        }
        return "Die Freigabe hat nicht geklappt. Bitte später erneut versuchen."
    }

    private func prepareShare() async {
        isPreparing = true
        errorMessage = nil
        defer { isPreparing = false }

        let cellar = Cellar.findOrCreateDefault(in: context)
        do {
            // Eine bereits angelegte Freigabe wiederverwenden, sonst entstehen Dubletten.
            if let existing = share {
                cloudContainer = CKContainer(identifier: PersistenceController.cloudContainerIdentifier)
                _ = existing
                isShowingSharingSheet = true
                return
            }
            let (newShare, container) = try await PersistenceController.shared.share(cellar)
            share = newShare
            cloudContainer = container
            isShowingSharingSheet = true
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
    }
}
