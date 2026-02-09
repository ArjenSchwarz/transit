//
//  ProjectColorDot.swift
//  Transit
//
//  Rounded square color indicator for projects.
//

import SwiftUI

struct ProjectColorDot: View {
    let color: Color
    let size: CGFloat

    init(color: Color, size: CGFloat = 20) {
        self.color = color
        self.size = size
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(width: size, height: size)
    }
}
