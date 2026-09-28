import Foundation

@main enum OrderListDragLayoutTests {
    static func main() {
        let fixtures: [[CGFloat]] = [
            [100, 40, 80, 40], // CPU/detail row crossing several unequal rows.
            [40, 40, 112, 40], // Quota row with explanatory text.
            [28, 28, 28], // Equal rows, including heights below the old 36pt clamp.
            [52],
        ]
        var cases = 0
        for heights in fixtures {
            let indices = Array(heights.indices)
            let oldTops = tops(order: indices, heights: heights)
            for origin in indices {
                for destination in indices {
                    var order = indices
                    order.insert(order.remove(at: origin), at: destination)
                    let newTops = tops(order: order, heights: heights)
                    for index in indices where index != origin {
                        let offset = OrderListDragLayout.offset(
                            index: index, origin: origin, destination: destination,
                            draggedHeight: heights[origin]
                        )
                        assert(oldTops[index]! + offset == newTops[index]!,
                               "Wrong position for row \(index), move \(origin) -> \(destination)")
                    }
                    // Non-dragged rows preserve their final separation without overlap.
                    let stationary = order.filter { $0 != origin }
                    for (first, second) in zip(stationary, stationary.dropFirst()) {
                        let firstBottom = newTops[first]! + heights[first]
                        assert(newTops[second]! - firstBottom >= OrderListDragLayout.spacing)
                    }
                    cases += 1
                }
            }
        }
        assert(OrderListDragLayout.offset(index: 1, origin: 0, destination: 2, draggedHeight: 0) == 0)
        print("Order list drag layout tests passed (\(cases) reorder cases)")
    }

    static func tops(order: [Int], heights: [CGFloat]) -> [Int: CGFloat] {
        var result: [Int: CGFloat] = [:]
        var y: CGFloat = 0
        for index in order {
            result[index] = y
            y += heights[index] + OrderListDragLayout.spacing
        }
        return result
    }
}
