import SwiftUI
import CoreData
import UniformTypeIdentifiers

/// Shown during onboarding (and from the home screen empty state) when a user
/// already tracks their collection in a spreadsheet and wants to import it.
struct CSVImportOnboardingView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// Called after a successful import or after the user taps "Done" on the
    /// prepare-instructions screen.  Lets the caller (OnboardingView / HomeView)
    /// finish the flow (e.g. mark onboarding complete).
    var onComplete: (() -> Void)? = nil

    // ── State ──────────────────────────────────────────────────────────────
    @State private var screen: Screen = .choice
    @State private var showingFilePicker = false
    @State private var isImporting = false
    @State private var importError: String? = nil
    @State private var showingError = false
    @State private var importSuccess = false

    private enum Screen { case choice, prepare, importing }

    // ── Palette (matches OnboardingView) ──────────────────────────────────
    private let gold      = Color(red: 0.84, green: 0.63, blue: 0.24)
    private let richAmber = Color(red: 0.60, green: 0.30, blue: 0.06)
    private let deepAmber = Color(red: 0.48, green: 0.22, blue: 0.04)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [gold.opacity(0.12), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            switch screen {
            case .choice:   choiceScreen
            case .prepare:  prepareScreen
            case .importing: importingScreen
            }
        }
        .sheet(isPresented: $showingFilePicker) {
            DocumentPicker(supportedTypes: [UTType.commaSeparatedText, UTType.text]) { url in
                handlePickedFile(url: url)
            }
        }
        .alert("Import Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importError ?? "Something went wrong. Please check your CSV file and try again.")
        }
    }

    // ── Choice screen ──────────────────────────────────────────────────────
    private var choiceScreen: some View {
        VStack(spacing: 0) {
            // Dismiss / back
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                        .padding()
                }
                Spacer()
            }

            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [gold.opacity(0.25), gold.opacity(0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 130, height: 130)
                Image(systemName: "tablecells")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(LinearGradient(
                        colors: [gold, deepAmber],
                        startPoint: .top, endPoint: .bottom))
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.bottom, 28)

            VStack(spacing: 10) {
                Text("Import Your Collection")
                    .font(.title2).bold()
                    .multilineTextAlignment(.center)
                Text("Already tracking bottles in a spreadsheet?")
                    .font(.title3)
                    .foregroundColor(gold)
                    .multilineTextAlignment(.center)
                Text("Use the BarrelBook CSV template and import your entire collection in seconds.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                // Primary: show me how (most users need this first)
                Button {
                    withAnimation { screen = .prepare }
                } label: {
                    HStack {
                        Text("Show me how to import").font(.headline)
                        Image(systemName: "doc.text")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(gold.gradient)
                    .cornerRadius(15)
                }

                Text("You will need to use the BarrelBook template before importing. Tap above to get started.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.horizontal)
            .padding(.bottom, 36)
        }
    }

    // ── Prepare screen ─────────────────────────────────────────────────────
    private var prepareScreen: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation { screen = .choice }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(gold)
                    .padding()
                }
                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(spacing: 8) {
                        Text("How to Import")
                            .font(.title2).bold()
                        Text("Three quick steps and your collection is in.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Already have a spreadsheet? If your columns are close to the template format, it usually takes just a few tweaks to get it import-ready.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)

                    VStack(spacing: 20) {
                        stepRow(
                            number: "1",
                            title: "Get the template",
                            detail: "In BarrelBook, go to Settings → Data Management → Export CSV Template. Open the file on your Mac or PC.",
                            icon: "arrow.down.doc"
                        )
                        stepRow(
                            number: "2",
                            title: "Fill in your bottles",
                            detail: "Add one row per bottle. Required columns are Name and Distillery. Everything else is optional.",
                            icon: "pencil"
                        )
                        stepRow(
                            number: "3",
                            title: "Come back and import",
                            detail: "Return here and tap \"I have my CSV ready\", or go to Settings → Data Management → Import CSV.",
                            icon: "arrow.up.doc"
                        )
                    }

                    // Tip box
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(gold)
                            .padding(.top, 2)
                        Text("Tip: Column headers must match the template exactly. You can also export from a spreadsheet app like Excel or Numbers.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(gold.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(gold.opacity(0.2), lineWidth: 1))
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 36)
            }

            // Done button
            Button {
                onComplete?()
                dismiss()
            } label: {
                Text("Got it, take me to the app")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(gold.gradient)
                    .cornerRadius(15)
            }
            .padding(.horizontal)
            .padding(.bottom, 36)
        }
    }

    // ── Importing screen ───────────────────────────────────────────────────
    private var importingScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .scaleEffect(1.6)
                .tint(gold)
            Text("Importing your collection...")
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // ── Step row helper ────────────────────────────────────────────────────
    private func stepRow(number: String, title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(gold.opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(number)
                    .font(.headline)
                    .foregroundColor(gold)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline).fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    // ── Import logic ───────────────────────────────────────────────────────
    private func handlePickedFile(url: URL) {
        withAnimation { screen = .importing }
        isImporting = true

        Task {
            do {
                guard url.startAccessingSecurityScopedResource() else {
                    throw ImportError.permissionDenied
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let csvString = try String(contentsOf: url, encoding: .utf8)
                try await CSVService().importWhiskeys(from: csvString, context: viewContext, isFreshImport: false)

                await MainActor.run {
                    isImporting = false
                    HapticManager.shared.successFeedback()
                    onComplete?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    importError = error.localizedDescription
                    showingError = true
                    withAnimation { screen = .choice }
                }
            }
        }
    }

    private enum ImportError: LocalizedError {
        case permissionDenied
        var errorDescription: String? {
            "Permission denied: unable to access the selected file."
        }
    }
}

#Preview {
    CSVImportOnboardingView()
}
