import SwiftUI
import UniformTypeIdentifiers

/// Node Studio upload form: pick an audio file, set title/artist/album and
/// optional time-coded lyrics, then start a background upload (with Live Activity).
struct TrackUploadSheet: View {
    let isEnglish: Bool
    let accent: Color
    var defaultArtist: String = ""
    var onClose: () -> Void

    @ObservedObject private var uploader = TrackUploadManager.shared

    @State private var pickedFileURL: URL?
    @State private var pickedFileName: String = ""
    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var lyrics = ""
    @State private var showFileImporter = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    filePicker
                    field(title: isEnglish ? "Title" : "Название",
                          text: $title,
                          placeholder: isEnglish ? "Track title" : "Название трека")
                    field(title: isEnglish ? "Artist" : "Артист",
                          text: $artist,
                          placeholder: isEnglish ? "Artist name" : "Имя артиста")
                    field(title: isEnglish ? "Album" : "Альбом",
                          text: $album,
                          placeholder: isEnglish ? "Album (optional)" : "Альбом (необязательно)")
                    lyricsEditor
                    uploadButton
                }
                .padding(20)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(isEnglish ? "Upload track" : "Загрузка трека")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEnglish ? "Close" : "Закрыть") { onClose() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { if artist.isEmpty { artist = defaultArtist } }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                pickedFileURL = url
                pickedFileName = url.lastPathComponent
                if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
            }
        }
    }

    private var filePicker: some View {
        Button { showFileImporter = true } label: {
            HStack(spacing: 14) {
                Image(systemName: pickedFileURL == nil ? "waveform.badge.plus" : "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(pickedFileURL == nil ? .white : Color.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pickedFileURL == nil
                         ? (isEnglish ? "Choose MP3 / audio" : "Выбрать MP3 / аудио")
                         : pickedFileName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(isEnglish ? "MP3, M4A, WAV, FLAC" : "MP3, M4A, WAV, FLAC")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4))
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private func field(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            TextField("", text: text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.35)))
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var lyricsEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isEnglish ? "Lyrics" : "Текст")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text(isEnglish
                 ? "Plain text, or add a timestamp like [1:12] before a line to sync it."
                 : "Простой текст, либо добавь метку [1:12] перед строкой для синхронизации по времени.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
            ZStack(alignment: .topLeading) {
                if lyrics.isEmpty {
                    Text("[0:00] …")
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                }
                TextEditor(text: $lyrics)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                    .padding(8)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var uploadButton: some View {
        Button {
            guard let url = pickedFileURL else { return }
            uploader.upload(
                fileURL: url,
                title: title.isEmpty ? pickedFileName : title,
                artistName: artist,
                album: album,
                lyrics: lyrics
            )
            onClose()
        } label: {
            Text(uploader.isUploading
                 ? (isEnglish ? "Uploading…" : "Загрузка…")
                 : (isEnglish ? "Upload" : "Загрузить"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(pickedFileURL == nil || uploader.isUploading)
        .opacity(pickedFileURL == nil || uploader.isUploading ? 0.4 : 1)
        .padding(.top, 4)
    }
}
