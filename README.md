# P4Runtime-CPUport-finder
Simple tool to identify the CPU port number on P4Runtime

See [Japanese document](README_ja.md).

### Introduction

This little P4 switch program is intended to clarify the CPU port number of the switch you are using with the P4 Runtime.

For example, the common simple_switch_grpc switch running under [P4 Runtime-enabled Mininet Docker Image](https://hub.docker.com/r/opennetworking/p4mn) uses 255 for the CPU port because it happens to pass the `--cpu-port 255` option at boot time. The default CPU port for simple_switch_grpc is 511, but it is [Set to 255 because it conflicts with the drop port](https://github.com/p4lang/behavioral-model/issues/831).

Wedge 100BF-65X and 100BF-32X switches with Tofino chip have different CPU port numbers. Even if you read the material, the explanation about the CPU port is scattered, and it is best to ask the switch to determine what number is used for this switch.

In the P4 Runtime, when the switch receives a Packet-Out, the ingress port is exactly the CPU port of the switch. cpuport_finder.p4 stores this information in the ingress port of the Packet-In header and transmit it to the port specified by Packet-Out. If you look at the first 9 bits of the packet coming out of the switch, you should be able to read the CPU port number there.

Here are the steps:

### Step 1. Preparing the switch (starting the Mininet environment)

We will use [P4 Runtime-enabled Mininet Docker Image](https://hub.docker.com/r/opennetworking/p4mn) as our switch. Here's how to get started.

Start the Mininet environment that supports P4Runtime in the Docker environment. Note that the --arp and --mac options are specified at startup so that ping tests can be performed without ARP processing.

```bash
$ docker run --privileged --rm -it -p 50001:50001 opennetworking/p4mn --arp --topo single,2 --mac
*** Error setting resource limits. Mininet's performance may be affected.
*** Creating network
*** Adding controller
*** Adding hosts:
h1 h2 
*** Adding switches:
s1 
*** Adding links:
(h1, s1) (h2, s1) 
*** Configuring hosts
h1 h2 
*** Starting controller

*** Starting 1 switches
s1 .⚡️ simple_switch_grpc @ 50001

*** Starting CLI:
mininet>
```

You can see that port 1 of s1 is connected to h1 and port 2 is connected to h2.

```bash
mininet> net
h1 h1-eth0:s1-eth1
h2 h2-eth0:s1-eth2
s1 lo:  s1-eth1:h1-eth0 s1-eth2:h2-eth0
mininet> 
```

Now monitor and observe the eth0 port of h1 in Mininet (h1-eth0). It is convenient to add -XX to tcpdump to show the hex dump of the whole header.

```bash
mininet> h1 tcpdump -XX -i h1-eth0
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on h1-eth0, link-type EN10MB (Ethernet), capture size 262144 bytes
```
At this point, the tcpdump command will wait in this state.

### Step 2. Starting P4Runtime Shell

```bash
Cecil(133)% docker run -it -v /tmp/:/tmp/ yutakayasuda/p4runtime-shell-dev /bin/bash
root@d633c64bbb3c:/p4runtime-sh# . activate 
(venv) root@d633c64bbb3c:/p4runtime-sh# 

(venv) root@d633c64bbb3c:/p4runtime-sh# cd /tmp
(venv) root@d633c64bbb3c:/tmp# ls 
cpuport_finder.json  p4info.txt  pout_exp_1.txt
(venv) root@d633c64bbb3c:/tmp# 
```
It synchronizes the/tmp directory on the host with the /tmp directory on the docker and places the switch-related files in this repository.

If you are using a different switch or P4 runtime environment, such as the Wedge 100BF-32X, please recompile cpuport_finder.p4 for your environment.

Then connect to Mininet as follows. Adjust the IP address to your environment.

```bash
(venv) root@d633c64bbb3c:/tmp# /p4runtime-sh/p4runtime-sh --grpc-addr 192.168.XX.XX:50001 --device-id 1 --election-id 0,1 --config p4info.txt,cpuport_finder.json
*** Welcome to the IPython shell for P4Runtime ***
P4Runtime sh >>>
```

### Step 3. Packet Out operation

Do the Request() function on the P4 Runtime Shell side. The Request() function is what I added to the standard P4 Runtime Shell. It reads the message content from the specified file then sends it to the switch as a P4 Runtime StreamMessageRequest message. 

No return value or message is returned. The contents of the message to be sent are printed on the screen.

```bash
P4Runtime sh >>> Request("pout_exp_1.txt")
packet {
  payload: "\377\377\377\377\377\377\000\001\000\001\000\001\210\265\000\00001234567890123456789012345678901234567890123456789012345678901234567890123456789"
  metadata {
    metadata_id: 1
    value: "\000\001"
  }
}
P4Runtime sh >>>
```

The value: in the file to be read is the output port number to Packet-Out. In this case, port 1 is specified. Please change this part to a switch number that is convenient for you.

The payload part, that is, the contents of the packet to be Packet-Out, is as follows.

```pseucode
dest: ff:ff:ff:ff:ff:ff 
src : 00:01:00:01:00:01
type: 88b5 (IEEE Local experimental)
body: NULL, NULL, "0123.... (80bytes)"
```

### Step 4. Output packet detection

In this state, the result of tcpdump that you ran in Step 1 should look like this:
```bash
09:16:34.625856 00:01:00:01:00:01 (oui Unknown) > Broadcast, ethertype Unknown (0x88b5), length 98:
        0x0000:  ffff ffff ffff 0001 0001 0001 88b5 7f80  ................
        0x0010:  0000 3031 3233 3435 3637 3839 3031 3233  ..01234567890123
        0x0020:  3435 3637 3839 3031 3233 3435 3637 3839  4567890123456789
        0x0030:  3031 3233 3435 3637 3839 3031 3233 3435  0123456789012345
        0x0040:  3637 3839 3031 3233 3435 3637 3839 3031  6789012345678901
        0x0050:  3233 3435 3637 3839 3031 3233 3435 3637  2345678901234567
        0x0060:  3839                                     89
```

The received packet is almost the same as what should have been Packet-Out described above. The difference is that 15-16 bytes are inserted after the 14-bytes Ethernet Header (dest, src, type). The body is transmitted as it is from the 17th byte. The format of inserted 2 bytes at the 15-16 byte position is defined by cpuport_header_t in cpuport_finder.p4.

```C++
header cpuport_header_t {
    bit<9> port;
    bit<7> _pad;
}
```
Added 2 bytes is 0x7f80. 7f in the first byte is 0111-1111, and 80 in the second byte is 1000-0000. If we extract only 9 bits from the most significant bit (left side), we see 0111-1111-1, which is ff in hexadecimal and 255 in decimal.

When I did the same operation on my Wedge 100BF-32X (Barefoot SDE 8.9.2), these 2 bytes were x6000. When the x6000 is truncated at the first 9 bits, it is confirmed that it matches the correct CPU port number in this environment, 192.
