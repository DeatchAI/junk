import CoreImage.CIFilterBuiltins

enum MessagesQRCode {
  static func image(for payload: String) -> CGImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(payload.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }
    return CIContext().createCGImage(output, from: output.extent)
  }
}

