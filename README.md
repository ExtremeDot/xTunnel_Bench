# xTunnel_Bench
----

### Install Script

```
bash <(wget -qO- https://raw.githubusercontent.com/ExtremeDot/xTunnel_Bench/main/frp_manager.sh)
```

یا بصورت نصب در لینوکس و استفاده آفلاین

```
curl -sSL -o /usr/local/bin/frp_manager.sh https://raw.githubusercontent.com/ExtremeDot/xTunnel_Bench/main/frp_manager.sh && chmod +x /usr/local/bin/frp_manager.sh && /usr/local/bin/frp_manager.sh
```

بعد با دستور زیر اجرا کنید

```
frp_manager.sh
```

------

<img width="805" height="664" alt="image" src="https://github.com/user-attachments/assets/7041839d-afc5-43c9-8eb0-3714a21cf093" />


### Install Dependencies and FRP Binaries

```
1. Install Dependencies & FRP v0.70.1
````


Then Check Server Location to be Correct

Server Location Status: [ KHAREJ ] or Server Location Status: [ IRAN ]
if Wrong change it via Menu:

```
8. Change Location Mode Manually (Toggle Iran/Kharej)
```

---

2- First Setup IRAN 

```
2. Setup FRP Server (Iran - Run on IRAN Server)
```
to generate Authentication Token use command:

```
tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24; echo
```

<img width="654" height="464" alt="image" src="https://github.com/user-attachments/assets/b76e189c-5440-4f46-bcea-f24cdee0fdb9" />



---

3-  Setup Kharej Server

```
3. Setup FRP Client (Kharej - Run on KHAREJ Server)
```

<img width="629" height="335" alt="image" src="https://github.com/user-attachments/assets/22ac86b6-63b1-480b-8e76-652fe11ff209" />



-------



