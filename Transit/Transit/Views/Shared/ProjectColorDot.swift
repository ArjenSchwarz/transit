import SwiftUI

struct ProjectColorDot: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(width: 12, height: 12)
    }
}
