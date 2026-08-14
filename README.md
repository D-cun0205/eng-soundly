# EngSoundly

한국인 영어 학습자를 위한 발음 진단 iOS 앱.
사용자의 발음을 듣고 **실제로 낸 소리(IPA)** 를 인식해, 미국 영어 원어민 발음과의
차이를 한국어 화자 특유의 간섭 패턴(L1 interference) 관점에서 설명하고 교정법을 제시한다.

## 파이프라인

```
녹음 (16kHz mono)
  → 음소 인식 (wav2vec2 phoneme CTC, Core ML, 온디바이스)
  → 목표 발음 (CMUdict ARPAbet → canonical IPA)
  → 정렬 (Needleman–Wunsch, 음성학적 자질 기반 비용)
  → 한국인 L1 규칙 매칭 (r/l, f/p, θ/s, 모음 삽입 등 15종)
  → 한국어 설명 + 조음 교정 팁 + 원어민 TTS 대조
```

핵심 설계: 일반 음성인식(ASR)은 문맥 보정 때문에 "말하려던 단어"를 돌려주므로 쓸 수 없다.
음소 CTC 모델은 "실제로 낸 소리"를 IPA로 출력하므로 발음 진단이 가능하다.
판정은 규칙 기반(결정적), 설명은 사전 작성된 한국어 규칙 카드가 담당한다.

## 구조

| 경로 | 역할 |
|---|---|
| `Sources/Models/PhonemeMapping.swift` | 표준 음소 집합, ARPAbet→IPA, espeak 정규화, 자질 테이블 |
| `Sources/Diagnosis/PhonemeAligner.swift` | 자질 비용 기반 전역 정렬 |
| `Sources/Diagnosis/KoreanL1Rules.swift` | 한국인 간섭 패턴 규칙 15종 (한국어 설명 포함) |
| `Sources/Diagnosis/DiagnosisEngine.swift` | 변이형 선택, 이슈 생성, 점수 계산 |
| `Sources/Services/PhonemeRecognizer.swift` | Core ML CTC 인식기 + 데모용 목 |
| `Sources/Services/AudioRecorder.swift` | AVAudioEngine 16kHz 캡처, 무음 트리밍 |
| `Sources/Services/PronunciationDictionary.swift` | CMUdict 로더 (13.5만 단어) |
| `Resources/words.json` | 카테고리별 연습 단어 (최소대립쌍 포함) |
| `Tools/convert_model.py` | wav2vec2-lv-60-espeak-cv-ft → Core ML 변환 |

## 빌드

```bash
xcodegen generate
xcodebuild -project EngSoundly.xcodeproj -target EngSoundly -sdk iphonesimulator build
```

유닛 테스트(진단 엔진, macOS에서 실행):

```bash
swift test
```

## 실기기 배포

1회 준비 (Apple ID 필요, 직접 수행):

1. **Xcode > Settings > Accounts**에서 Apple ID 로그인 — 무료 계정도 개인 기기
   테스트 가능 (프로비저닝 7일 유효, 유료 Developer Program은 1년 + TestFlight)
2. iPhone 케이블 연결 → "이 컴퓨터를 신뢰" 허용
3. iPhone 설정 > 개인정보 보호 및 보안 > **개발자 모드** 켜기 → 재부팅
4. 팀 ID 확인 (Xcode Accounts 화면 Team 항목, 형식: `AB12CD34EF`)

이후 배포는 한 줄:

```bash
./Tools/deploy_device.sh <TEAM_ID>
```

빌드(Release) → 자동 서명 → 기기 설치 → 실행까지 수행한다. 무료 계정이면 첫 실행
전에 기기의 설정 > 일반 > VPN 및 기기 관리에서 개발자 앱 신뢰가 필요하다.

App Store 배포 시에는 레거시 방식으로 번들한 앱 아이콘을 Asset Catalog
(`Resources/Assets.xcassets`, 현재 빌드 제외 상태)으로 되돌려야 한다 — 이 머신의
actool이 SDK/런타임 불일치로 깨져 있어 우회한 것.

## 음향 모델

번들에 `PhonemeCTC.mlpackage` + `phoneme_vocab.json`이 없으면 **데모 모드**로 동작한다
(전형적 한국인 오류를 주입한 예시 진단 표시).

실제 모델 생성:

```bash
cd Tools
/opt/homebrew/opt/python@3.11/bin/python3.11 -m venv venv
./venv/bin/pip install torch transformers coremltools numpy
./venv/bin/python convert_model.py    # → PhonemeCTC.mlpackage (~600MB fp16)
./venv/bin/python quantize_model.py   # → int8 per-channel, ~300MB
mv ../Resources/PhonemeCTC_int8.mlpackage ../Resources/PhonemeCTC.mlpackage
cd .. && xcodegen generate            # 후 재빌드
```

모델: [facebook/wav2vec2-lv-60-espeak-cv-ft](https://huggingface.co/facebook/wav2vec2-lv-60-espeak-cv-ft)
(다국어 음소 인식, espeak IPA 출력). 앱은 int8 양자화본(302MB)을 사용하며,
5단어 합성음 회귀셋에서 fp16과 인식 출력이 동일함을 확인했다.

## 로드맵

1. ✅ 단어 단위 MVP (음소 진단 + 규칙 카드 + TTS 대조)
2. 문장 단위 — 연음 변이형 생성·정렬, 강세/리듬 분석
3. 개인화 — 음소별 오류율 추적, 취약 음소 드릴
