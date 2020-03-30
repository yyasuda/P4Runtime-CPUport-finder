# P4Runtime-CPUport-finder
Simple tool to identify the CPU port number on P4Runtime

### はじめに

この小さな P4 スイッチプログラムは、自分が P4 Runtime で使っているスイッチの CPU port 番号をハッキリさせるためのものです。

例えばよく使われるであろう [P4Runtime-enabled Mininet Docker Image](https://hub.docker.com/r/opennetworking/p4mn) 環境で動作している simple_switch_grpc スイッチが CPU port に 255 を使っているのは、たまたま起動時に `--cpu-port 255` オプションを渡しているからです。simple_switch_grpc のデフォルトの CPU port は 511 なのですが、それは [drop port と衝突するので 255 に設定された](https://github.com/p4lang/behavioral-model/issues/831)だけです。

また Tofino チップを積んだ Wedge スイッチでは、100BF-65X と 100BF-32X で CPU ポート番号が異なります。資料を読んでいてもCPU port に関する説明は散在しており、果たしていまこのスイッチで使っている番号が何番なのか確定させるためには、やはりスイッチに聞くのが一番です。

P4Runtime では、Packet-Out をスイッチが受けたとき、その ingress port がまさにスイッチが認識している CPU port に当たります。cpuport_finder.p4 は、この情報を Packet-In ヘッダの ingress port に格納して、Packet-Out が指定する port に出力します。スイッチから出てきたパケットの先頭 9bit を見れば、そこに CPU port の番号を読み取ることが出来るはずです。

以下に作業手順を示します。

### Step 1. スイッチの準備（Mininet 環境の立ち上げ）

ここでは [P4Runtime-enabled Mininet Docker Image](https://hub.docker.com/r/opennetworking/p4mn) をスイッチとして利用します。以下のようにして起動すると良いでしょう。

P4Runtimeに対応した Mininet 環境を、Docker環境で起動します。起動時に --arp と --mac オプションを指定して、ARP 処理無しに ping テストなどができるようにしてあることに注意してください。

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

s1 の port 1 が h1 に、port2 が h2 に接続されていることが確認できます。

```bash
mininet> net
h1 h1-eth0:s1-eth1
h2 h2-eth0:s1-eth2
s1 lo:  s1-eth1:h1-eth0 s1-eth2:h2-eth0
mininet> 
```

ここで以下のようにして、Mininet の h1 の eth0 ポート（h1-eth0）をモニタリングして見張っておきます。tcpdump には -XX を付けるとヘッダごと hexdump してくれて便利ですね。

```bash
mininet> h1 tcpdump -XX -i h1-eth0
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on h1-eth0, link-type EN10MB (Ethernet), capture size 262144 bytes
```
ここで待ち状態になるでしょう。

### Step 2. P4Runtime Shellの起動

```bash
Cecil(133)% docker run -it -v /tmp/ether_switch/:/tmp/ yutakayasuda/p4runtime-shell-dev /bin/bash
root@d633c64bbb3c:/p4runtime-sh# . activate 
(venv) root@d633c64bbb3c:/p4runtime-sh# 

(venv) root@d633c64bbb3c:/p4runtime-sh# cd /tmp
(venv) root@d633c64bbb3c:/tmp# ls
ether_switch.json  ether_switch.p4  ether_switch.p4i  p4info.txt
(venv) root@d633c64bbb3c:/tmp# 
```
ホストの /tmp/ether_switch ディレクトリと docker の /tmp を同期させて、そこにこのリポジトリにあるスイッチ関連ファイルを置いています。

もしあなたが Wedge 100BF-32X など、異なるスイッチや P4 実行環境を使っている場合は、cpuport_finder.p4 を自分の環境に合わせてコンパイルし直してください。

続いて、以下のようにして Mininet に接続します。IPアドレスは自身の環境に合わせて下さい。

```bash
(venv) root@d633c64bbb3c:/tmp# /p4runtime-sh/p4runtime-sh --grpc-addr 192.168.XX.XX:50001 --device-id 1 --election-id 0,1 --config p4info.txt,ether_switch.json
*** Welcome to the IPython shell for P4Runtime ***
P4Runtime sh >>>
```

### Step 3. Packet Out 操作

P4Runtime Shell 側で Request() 関数を起動します。Request() 関数は私が標準の P4Runtime Shell に追加した機能です。指定されたファイルからメッセージ内容を読み取り、これをP4RuntimeのStreamMessageRequest メッセージとしてスイッチに送り込みます。
特に戻り値やメッセージは返ってきません。画面上には送信するメッセージの内容がprintされます。

```bash
P4Runtime sh >>> Request("/tmp/packetout.txt")                                                                                             
packet {
  payload: "\377\377\377\377\377\377\377\377\377\377\377\377\000\000ABCDEFGHIJKLMN"
  metadata {
    metadata_id: 1
    value: "\000\001"
  }
}
P4Runtime sh >>> 
```

読み込ませるファイルの中の value: の値が Packet-Out する出力先ポート番号です。ここでは port 1 に出力させています。この部分をあなたにとって都合の良いスイッチ番号に切り替えて使ってください。

### Step 4. 出力パケットの検出

この状態で、Step 1. で実行していた tcpdump の結果に、以下のような表示が出ているでしょう。
```bash
09:41:30.049074 Broadcast > 7f:80:ff:ff:ff:ff (oui Unknown), ethertype Unknown (0xffff), length 30: 
	0x0000:  7f80 ffff ffff ffff ffff ffff ffff 0000  ................
	0x0010:  4142 4344 4546 4748 494a 4b4c 4d4e       ABCDEFGHIJKLMN
```

先頭 1 バイト目が 7f つまり 0111-1111、2 バイト目が 80 つまり 1000-0000 です。最上位ビット（左側）から 9 bit だけ取り出すと、0111-1111-1 つまり16 進数で ff、10 進数では 255 であることが分かります。

筆者が使用している Wedge 100BF-32X では、正しく 192 になることを確認しています。





Yutaka Yasuda, Kyoto Sangyo University

