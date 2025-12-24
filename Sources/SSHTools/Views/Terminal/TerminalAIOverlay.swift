import SwiftUI

struct AIStep: Identifiable, Decodable {
    let id = UUID()
    let desc: String
    let cmd: String
    var isExecuted: Bool = false // Local state for UI
    
    private enum CodingKeys: String, CodingKey {
        case desc, cmd
    }
}

struct TerminalAIOverlay: View {
    @Binding var isPresented: Bool
    @Binding var prompt: String
    @Binding var isGenerating: Bool
    
    // New: Steps support
    @Binding var steps: [AIStep]
    let onGenerate: () -> Void
    let onExecuteStep: (AIStep) -> Void
    
    var body: some View {
        Group {
            if isPresented {
                VStack(spacing: 0) {
                    // Input Header
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                        
                        TextField("Describe what you want to do...", text: $prompt)
                            .textFieldStyle(.plain)
                            .foregroundColor(.black)
                            .onSubmit { 
                                steps = [] // Clear previous steps
                                onGenerate() 
                            }
                        
                        if isGenerating {
                            ProgressView().scaleEffect(0.5)
                        } else {
                            if steps.isEmpty {
                                Button(action: onGenerate) {
                                    Text("Generate")
                                        .font(.caption.bold())
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.blue)
                            } else {
                                Button("Clear") {
                                    withAnimation {
                                        steps = []
                                        prompt = ""
                                    }
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                        
                        Button(action: { withAnimation { isPresented = false } }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .padding(4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    
                    // Steps List
                    if !steps.isEmpty {
                        Divider()
                        List {
                            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                                HStack {
                                    // Status Icon
                                    Image(systemName: step.isExecuted ? "checkmark.circle.fill" : "\(index + 1).circle")
                                        .foregroundColor(step.isExecuted ? .green : .secondary)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(step.desc)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.black)
                                        Text(step.cmd)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: { onExecuteStep(step) }) {
                                        Image(systemName: "play.fill")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                            .padding(4)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .frame(height: min(CGFloat(steps.count * 44 + 20), 300)) // Dynamic height up to 300
                        .listStyle(.plain)
                    }
                }
                .frame(width: 320) // Side panel width
                .background(Color.white)
                .cornerRadius(8)
                .shadow(radius: 5)
                .padding()
                .onExitCommand {
                    withAnimation { isPresented = false }
                }
                .transition(.move(edge: .trailing))
            } else {
                Button(action: { withAnimation { isPresented = true } }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("AI Command")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.1))
                    .foregroundColor(.purple)
                    .cornerRadius(16)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
    }
}
