import ActivityKit
import WidgetKit
import SwiftUI

/// Progress info shown on the Lock Screen / Dynamic Island during a challenge.
///
/// NOTE (plan §4.4): the production app should present via AlarmKit's
/// `AlarmAttributes<PushupAlarmMetadata>`. This standalone attributes type is
/// the branded-UI placeholder so the widget target is complete and builds; wire
/// it to AlarmKit's presentation once testing the alarm path on a real device.
struct ChallengeActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var repsCompleted: Int
        public var repTarget: Int
    }
    public var label: String
}

struct ChallengeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChallengeActivityAttributes.self) { context in
            // Lock Screen / banner presentation.
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text(context.attributes.label).font(.headline)
                    Text("\(context.state.repsCompleted)/\(context.state.repTarget) pushups")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.repsCompleted)/\(context.state.repTarget)")
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.label).font(.caption)
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(.orange)
            } compactTrailing: {
                Text("\(context.state.repsCompleted)/\(context.state.repTarget)").monospacedDigit()
            } minimal: {
                Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(.orange)
            }
        }
    }
}
