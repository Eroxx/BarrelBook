import SwiftUI

struct LoadDemoConfirmationSheet: View {
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 24)

            // Icon
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundColor(ColorManager.primaryBrandColor)
                .padding(.bottom, 12)

            Text("Load Sample Data?")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.bottom, 12)

            Text("Explore BarrelBook with a pre-built bourbon collection.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)

            // Red warning box
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("This will permanently delete all your current bottles, tastings, and wishlist items.")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .cornerRadius(10)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            Text("Sample data can be removed anytime from the Home tab banner.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 28)

            VStack(spacing: 10) {
                Button(role: .destructive) {
                    dismiss()
                    onConfirm()
                } label: {
                    Text("Delete My Data & Load Sample Data")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red)
                        .cornerRadius(12)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .presentationDetents([.height(480)])
        .presentationDragIndicator(.hidden)
    }
}
