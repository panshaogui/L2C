# 1. 凭空造出一根虚拟网线，两头分别叫 veth-tx 和 veth-rx
sudo ip link add veth-tx type veth peer name veth-rx

# 2. 通电，把两头网卡启动
sudo ip link set veth-tx up
sudo ip link set veth-rx up

# 3. 给发射端配个假 IP，方便咱们一会儿拿它当靶子打
sudo ip addr add 10.99.99.1/24 dev veth-tx
sudo ip addr add 10.99.99.2/24 dev veth-rx

# sudo ip neigh add 10.99.99.100 lladdr aa:bb:cc:dd:ee:ff dev veth-tx

# echo -n "HFT!" | nc -u -w1 10.99.99.100 8888
