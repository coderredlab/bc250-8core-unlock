<div align="center">

# 🔓 BC-250 8코어 언락 펌웨어

**BIOS P3.00이 동작 중인 BC-250 보드를 위한 콜드 부팅 8코어/16스레드 언락**

[English](README.md) | **한국어**

![Platform](https://img.shields.io/badge/platform-AMD%20BC--250-00a4e4)
![BIOS](https://img.shields.io/badge/BIOS-P3.00-orange)
![Result](https://img.shields.io/badge/result-6C%2F12T%20%E2%86%92%208C%2F16T-brightgreen)
![Tested](https://img.shields.io/badge/tested%20on-real%20hardware-8A2BE2)
![License](https://img.shields.io/badge/code%20license-MIT-green)

*콜드 파워온 → 자동 리셋 1회 → 8코어 전부 활성화된 상태로 부팅.*

</div>

---

## ✨ 이 펌웨어가 다른 점

| | 이 펌웨어 | 기타 릴리스 다수 |
|---|---|---|
| 콜드 부팅 언락 | ✅ 자동 | ❌ 수동 도구 실행 + 수동 재부팅 |
| presence 검증 | ✅ 정확히 `0x77` 일치 시에만 동작 | 대체로 없음 |
| SMU 큐 폴링 | ✅ 상한 있음 — 2,500회 후 포기 | 무한 루프인 경우 많음 |
| 팩토리 퓨즈 확인 | ✅ 불량 마킹 보드는 거부 | 없음 |
| 실패 시 동작 | ✅ 순정 6코어 부팅으로 안전 강등 | 정의되지 않음 |
| 성공 시 리셋 | ✅ 검증된 flip 뒤 자동 1회 | 제각각 |

**실제 하드웨어에서 동작 확인 완료(2026-08-24):**
콜드 부팅 → 자동 리셋 1회 → `nproc` = 16, 이후 일일 시스템으로 안정 사용 중.

---

## ⛔ 가장 먼저 — 다른 어떤 것보다 먼저 읽으세요

> [!CAUTION]
> ### 이 언락은 불량 코어를 수리하지 않습니다
>
> BC-250은 출하 시 **소프트웨어적으로** 6코어로 제한되어 나옵니다. 이 펌웨어는
> 그 소프트웨어 게이트를 제거할 뿐입니다.
>
> **물리적으로 불량한 실리콘을 되살릴 수는 없습니다.** 사용 중인 칩이 추가
> 코어의 실제 불량 때문에 6코어로 출하된 것이라면, 강제로 온라인 상태로 만들면
> 부팅 실패나 불안정이 발생할 수 있습니다 — 그리고 언락 상태는 재부팅 사이에
> 유지되므로, 복구하려면 외부 SPI 프로그래머가 필요해집니다.

### ✅ 필수 사전 점검 (플래시 전 반드시 실행)

1. 순정 상태로 부팅한 뒤 휘발성 unlock을 먼저 실행합니다:
   [rw-r-r-0644/bc250-core-unlock](https://github.com/rw-r-r-0644/bc250-core-unlock)
2. 완료되면 웜 리부트합니다.
3. **8C/16T로 안정적으로 부팅된다면?** (`nproc` = 16, 스트레스 이상 없음) →
   코어가 건강하다는 뜻 → 이 영구 펌웨어를 적용해도 됩니다. ✔️
4. **부팅이 안 되거나, 크래시하거나, 6C/불안정하다면?** → 해당 코어가 불량일
   가능성이 높습니다 → **이 ROM을 플래시하지 마세요.** 순정을 유지하세요. ✖️

> [!NOTE]
> 제작자 본인 보드는 이 점검을 통과한 뒤(며칠간 안정적인 8C/16T 사용 + 코어별
> 연산 검증) 이미지를 만들었습니다.

펌웨어도 실행 시점에 자체 하드웨어 검사를 수행합니다: 호스트브릿지 ID,
마스크 값, 팩토리 퓨즈 레지스터(`0x5D25C`) — 이상이 감지되면 스스로 물러나고
stock 로직이 동작합니다.

---

## 📦 구성물

| 파일 | 설명 |
|---|---|
| `BC250-P3.00-8Core.rom` | 프로그래밍 준비된 16 MiB 풀 플래시 이미지 |

**SHA-256:**
```
1b7bcaa65e247363ad19e6a1dd3e296ae54b254fdeeeb32c8fb8ac505c86ac17
```

---

## 🚀 플래시 방법

> [!WARNING]
> - **P3.00**이 동작 중인 BC-250에만 사용하세요. 다른 버전은 테스트되지 않았습니다.
> - 기록 중 전원을 끊지 마세요.
> - 펌웨어 플래싱은 항상 위험을 수반합니다 — 본인 책임 하에 진행하세요.

### 방법 1 — Linux + flashrom *(권장, 이 보드에서 동작 확인됨)*

```bash
# 0) 먼저 현재 BIOS를 저장하세요 — 그것이 롤백용입니다!
sudo flashrom -p internal -r my-stock-backup.rom

# 1) 기록
sudo flashrom -p internal -w BC250-P3.00-8Core.rom

# 2) 독립 리드백 (건너뛰지 마세요!)
sudo flashrom -p internal -r verify.rom
sha256sum verify.rom   # 위 SHA-256과 일치해야 합니다
```

### 방법 2 — 외부 SPI 프로그래머 (CH341A 등)

칩을 탈착/소켓한 상태에서 이미지를 직접 기록합니다. 이 보드에서 탈착 +
외부 재기록이 성공한 실적이 있습니다.

---

## 🔎 플래시 후 언락 확인

```bash
nproc                       # 기대값: 16
grep -c ^processor /proc/cpuinfo
dmesg | grep -i "mce\|machine check"   # 비어 있어야 정상
```

선택적 스트레스 검증:

```bash
sudo apt install stress-ng
stress-ng --cpu 16 --cpu-method all --timeout 30m --metrics-brief
```

---

## 🔄 동작 참조

| 시나리오 | 결과 |
|---|---|
| 콜드 파워온 | PEIM 언락 → **자동 리셋 1회**(수 초) → 8C/16T 부팅 |
| 웜 리부트 | 리셋 없이 8C/16T 유지 |
| 언락 실패 시 | 안전한 순정 6코어 부팅 (설계상 hang 없음) |
| 완전 전원 차단 | 위 사이클이 딱 한 번 자동 반복 |

> [!NOTE]
> 콜드 부팅 시 리셋이 한 번 추가되는 것은 구조적 제약입니다: SMU는 삽입된
> PEIM이 실행되기 전에 코어 초기화를 마칩니다. 제거하려면 비공개 SMU 메시지의
> 리버스 엔지니어링이 필요합니다.

> [!TIP]
> 이미지에는 제작자의 NVRAM 값이 들어 있습니다. 첫 부팅 뒤 설정 메뉴가
> 이상하면 CMOS/NVRAM 클리어를 해보세요.

---

## ↩️ 롤백

퀵스타트 0단계에서 저장한 **본인의 순정 덤프**를 같은 방법으로 다시 기록하세요.
참고용 해시:

| 이미지 | SHA-256 (앞 16자) |
|---|---|
| 개발용 순정 P3.00 베이스 | `2854b3863b447e71` |
| 테스트 보드의 플래시 직전 스냅샷 | `ddb7f88e70bddcb7` |

잘못된 기록 뒤 리눅스 부팅이 아예 안 되는 경우: 외부 SPI 프로그래머에 본인의
순정 덤프를 올려 복구합니다. 이 보드에서 탈착 + 외부 재기록이 성공한 실적이
있습니다.

---

## 🧠 동작 원리

배포 이미지는 세 층으로 구성됩니다:

| 층 | 출처 | 내용 |
|---|---|---|
| 1 | 벤더 순정 P3.00 BIOS (AMI Aptio + AMD AGESA) | 기반 |
| 2 | [TuxThePenguin0/bc250-bios](https://gitlab.com/TuxThePenguin0/bc250-bios) | 칩셋 메뉴 노출 (~260KB 폼/IFR 변경) |
| 3 | **이 프로젝트** | CCX 바이트 patch + 언락 PEIM (아래) |

<details>
<summary><b>기술 변경 사항 (클릭해서 펼치기)</b></summary>

1. **AmdCcxVhAriPei**: OPN→downcore 토큰 변환의 immediate 1바이트(`07 → 00`) — CCX가 스스로 코어 게이트를 적용하지 않게 합니다(OPN Auto 동작).
2. **삽입된 PEIM (`Bc250CoreUnlockPei`)**: AMD NBIO SMU 서비스 PPI에 notify를 등록하고, core-presence 레지스터가 정확히 `0x77`인지 검증하며, 팩토리 core-disable 퓨즈 레지스터(`0x5D25C`)가 깨끗한지 확인합니다(출하 시 불량 마킹된 보드는 언락하지 않고 stock 유지). 이후 SMU Queue 3(메시지 `0x98`)으로 presence를 `0xff`로 flip — 바운드 폴링과 읽기 검증 포함 — 성공하면 PEI 리셋을 요청해 SMU가 전 코어를 활성화한 채 재초기화하게 합니다.

이 두 변경 외에는 위에서 설명한 CHIPSETMENU 베이스와 바이트 단위로 동일합니다.

</details>

### 자동 리셋이 필요한 이유

SMU는 삽입된 PEIM이 실행되기 **전에** 코어 초기화를 마칩니다. 따라서 새로
flip한 presence는 리셋을 한 번 거쳐야 효력이 생깁니다. presence는 웜 리셋을
건너므로, 자동 리부트 한 번이면 충분합니다. stock CCX도 downcore 설정 변경 시
같은 방식으로 PEI 리셋을 사용합니다 — 검증된 패턴입니다.

SMU Queue 3 프로토콜, PEI dispatch 분석, CCX downcore 결정 경로 등 전체
리버스 엔지니어링 노트는 메인 프로젝트의 리서치 wiki에 있습니다.

---

## 🙏 Credits

- [rw-r-r-0644/bc250-core-unlock](https://github.com/rw-r-r-0644/bc250-core-unlock) — SMU Queue 3 프로토콜 및 휘발성 언락 발견
- [TuxThePenguin0/bc250-bios](https://gitlab.com/TuxThePenguin0/bc250-bios) — 베이스 이미지 (`BC250_3.00_CHIPSETMENU.ROM`: 칩셋 메뉴 노출)
- [RescueMei/BC250-DXE-SMU-Core-Unlock](https://github.com/RescueMei/BC250-DXE-SMU-Core-Unlock) — 선행 연구
- [GabriWar/bc250-core-cu-unlock](https://github.com/GabriWar/bc250-core-cu-unlock) — 선행 연구
- [bc250-collective/amd_smu_reverse_engineering](https://github.com/bc250-collective/amd_smu_reverse_engineering) — SMU 리버스 엔지니어링

---

## 📄 License

소스 코드와 빌드 도구: **MIT License** ([`LICENSE`](LICENSE) 참조).

`.rom` 이미지는 보드 벤더의 순정 P3.00 BIOS(AMI Aptio + AMD AGESA)에서 파생된
펌웨어를 포함합니다. BC-250 하드웨어 소유자의 사용을 위해 as-is로 제공되며,
각 저작권은 원 소유자에게 있습니다.
