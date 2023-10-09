import NIO

protocol PartnerHandlerProtocol: AnyObject {
    func partnerWrite(_ data: NIOAny)
    func partnerFlush()
    func partnerWriteEOF()
    func partnerCloseFull()
    func partnerBecameWritable()
    var partnerWritable: Bool { get }
    var uuid: String { get set }
}
