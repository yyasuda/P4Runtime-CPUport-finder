#include <core.p4>
#include <v1model.p4>

typedef bit<48> macAddr_t;

@controller_header("packet_out")
header packet_out_header_t {
    bit<9> egress_port;
    bit<7> _pad;
}

@controller_header("packet_in")
header packet_in_header_t {
    bit<9> ingress_port;
    bit<7> _pad;
}

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16> etherType;
}

header cpuport_header_t {
    bit<9> port;
    bit<7> _pad;
}

struct metadata {
    /* empty */
}

struct headers {
    ethernet_t ethernet;
    cpuport_header_t cpuport;
    packet_out_header_t packet_out;
    packet_in_header_t packet_in;
}

parser MyParser(packet_in packet, out headers hdr, inout metadata meta,
                inout standard_metadata_t standard_metadata)
{
    state start {
        packet.extract(hdr.packet_out);
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition accept;
    }
}

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {  }
}

control MyIngress(inout headers hdr, inout metadata meta,
                    inout standard_metadata_t standard_metadata)
{
    apply {
      standard_metadata.egress_spec = hdr.packet_out.egress_port;
      hdr.packet_out.setInvalid();
      hdr.cpuport.setValid();
      hdr.cpuport.port = standard_metadata.ingress_port;
    }
}

control MyEgress(inout headers hdr, inout metadata meta,
                inout standard_metadata_t standard_metadata)
{
    apply { }
}

control MyComputeChecksum(inout headers  hdr, inout metadata meta)
{
    apply { }
}

control MyDeparser(packet_out packet, in headers hdr)
{
    apply {
        packet.emit(hdr.packet_out);
        packet.emit(hdr.packet_in);
        packet.emit(hdr.ethernet);
        packet.emit(hdr.cpuport);
    }
}

V1Switch(
    MyParser(),
    MyVerifyChecksum(),
    MyIngress(),
    MyEgress(),
    MyComputeChecksum(),
    MyDeparser()
) main;
