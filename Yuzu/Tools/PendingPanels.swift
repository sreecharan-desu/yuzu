import SwiftUI

/// Placeholders for panels still being built in phase 4.
private struct Pending: View {
    let env: ToolEnv
    var body: some View {
        ToolScaffold(env: env, primary: "Coming Soon", primaryEnabled: false, onPrimary: {}) {
            Text("\(env.tool.title) is coming in the next build.").foregroundStyle(.secondary)
        } controls: { EmptyView() }
    }
}
struct TrimPanel: View { let env: ToolEnv; var body: some View { Pending(env: env) } }
struct SpeedPanel: View { let env: ToolEnv; var body: some View { Pending(env: env) } }
struct SplitPanel: View { let env: ToolEnv; var body: some View { Pending(env: env) } }
struct CropVideoPanel: View { let env: ToolEnv; var body: some View { Pending(env: env) } }
struct BleepPanel: View { let env: ToolEnv; var body: some View { Pending(env: env) } }
struct ChannelsPanel: View { let env: ToolEnv; var body: some View { Pending(env: env) } }
struct SplitPDFPanel: View { let env: ToolEnv; var body: some View { Pending(env: env) } }
struct OrganizePanel: View { let env: ToolEnv; var body: some View { Pending(env: env) } }
