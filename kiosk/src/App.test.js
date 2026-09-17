import { readTrustworthyGps, normalizeBadgeUid, fetchPersonCards, regionQueries, LIST_TABS } from './App';

// 예전에는 CRA 기본 템플릿의 "learn react" 테스트가 그대로 남아 있었다.
// 이 앱에는 그런 문구가 없어서 처음부터 실패하고 있었고, 그래서 아무도 안 봤다.
//
// 여기서는 실제로 지킬 값어치가 있는 것 하나를 본다: 백엔드가 준 좌표를
// 보호자에게 보내도 되는지 판정하는 부분. 이게 느슨해지면 길 잃은 사람을
// 찾는 쪽에 엉뚱한 위치가 전달되므로 회귀가 나면 안 된다.

const iso = (msAgo) => new Date(Date.now() - msAgo).toISOString();
const REAL = { lat: 37.7093, lng: 126.8524 }; // 키오스크가 실제로 있는 동네

// reject 경로는 원인을 console.warn 으로 남긴다. 테스트 출력만 시끄러워지므로 막는다.
let warnSpy;
beforeEach(() => { warnSpy = jest.spyOn(console, 'warn').mockImplementation(() => {}); });
afterEach(() => { warnSpy.mockRestore(); });

describe('readTrustworthyGps - 믿을 수 있는 좌표만 통과시킨다', () => {
  test('ESP32가 방금 올린 좌표는 통과한다', () => {
    expect(readTrustworthyGps({ ...REAL, timestamp: iso(5000) })).toEqual(REAL);
  });

  test('문자열로 온 좌표도 숫자로 바꿔 통과시킨다', () => {
    expect(readTrustworthyGps({ lat: '37.7093', lng: '126.8524', timestamp: iso(1000) }))
      .toEqual(REAL);
  });

  test('서울시청 자리표시자 좌표는 거부한다', () => {
    // 배포된 키오스크가 실제로 이 값을 받아 버튼이 잘못 켜져 있었다.
    // ESP 가 꺼져 있는 동안 DB 에 남아 있던 시드 데이터다.
    expect(readTrustworthyGps({ lat: 37.5665, lng: 126.978, timestamp: iso(1000) })).toBeNull();
  });

  test('오래된 기록은 거부한다', () => {
    expect(readTrustworthyGps({ ...REAL, timestamp: iso(3600000) })).toBeNull();
  });

  test('측정 시각이 없으면 거부한다', () => {
    // 언제 잰 값인지 모르면 "지금 위치" 라고 볼 근거가 없다
    expect(readTrustworthyGps({ ...REAL })).toBeNull();
  });

  test('시계가 어긋나 미래 시각이 와도 거부한다', () => {
    // 라즈베리파이는 RTC 가 없어 NTP 가 붙기 전 시계가 튄다
    expect(readTrustworthyGps({ ...REAL, timestamp: iso(-3600000) })).toBeNull();
  });

  test('좌표가 없는 응답을 거부한다', () => {
    // 백엔드는 기록이 없으면 {"status":"error","message":"GPS 데이터가 없습니다."} 를 준다
    expect(readTrustworthyGps({ status: 'error', message: 'GPS 데이터가 없습니다.' })).toBeNull();
    expect(readTrustworthyGps(null)).toBeNull();
  });

  test('빈 값이 적도 위 좌표(0, 0)로 둔갑하지 않는다', () => {
    expect(readTrustworthyGps({ lat: '', lng: '', timestamp: iso(1000) })).toBeNull();
    expect(readTrustworthyGps({ lat: 0, lng: 0, timestamp: iso(1000) })).toBeNull();
  });

  test('범위를 벗어난 좌표는 거부한다', () => {
    expect(readTrustworthyGps({ lat: 999, lng: 126.8524, timestamp: iso(1000) })).toBeNull();
    expect(readTrustworthyGps({ lat: 'abc', lng: 'def', timestamp: iso(1000) })).toBeNull();
  });
});

// 실제로 쓰는 스티커 번호. 한 글자(3번째 바이트 76/75)만 달라서 눈으로는
// 구분이 어렵다. 짝이 뒤바뀌면 2호 키링을 든 사람에게 1호 위치가 가므로
// 여기서 고정해 둔다.
const UID_1 = '041d76922c2291'; // 1호 키링
const UID_2 = '041d75922c2291'; // 2호 키링

describe('normalizeBadgeUid - 표기가 달라도 같은 번호로 본다', () => {
  test('리더기가 주는 소문자 hex 는 그대로', () => {
    expect(normalizeBadgeUid(UID_1)).toBe(UID_1);
  });

  test('대문자와 구분자를 걷어낸다', () => {
    expect(normalizeBadgeUid('04:1D:76:92:2C:22:91')).toBe(UID_1);
    expect(normalizeBadgeUid('04-1d-76-92-2c-22-91')).toBe(UID_1);
  });

  test('문자열이 아니면 빈 값', () => {
    expect(normalizeBadgeUid(undefined)).toBe('');
    expect(normalizeBadgeUid(null)).toBe('');
  });
});

// 실종자 정보 화면. 탭이 엉뚱한 API 를 부르면 "보호 중이에요" 에 찾는 중인 사람이
// 섞여 나오고, 지역 조회가 헐거우면 그 지역 사람을 못 보고 지나친다.
describe('fetchPersonCards - 탭과 지역에 맞는 목록을 받아온다', () => {
  // 백엔드 카드 API 가 실제로 주는 모양
  const card = (over) => ({
    id: 553, name: '진대덕', gender_display: '남자', current_age: 67,
    category_display: '장애', photo: null, registered_date: '2026-09-13', ...over,
  });
  const serve = (pick) => jest.fn(async (url) => ({
    ok: true, status: 200, json: async () => pick(decodeURIComponent(url)),
  }));
  const calledUrls = () => global.fetch.mock.calls.map(([url]) => decodeURIComponent(url));

  let originalFetch;
  beforeEach(() => { originalFetch = global.fetch; });
  afterEach(() => { global.fetch = originalFetch; });

  test('처음 뜨는 탭은 찾는 중이에요', () => {
    expect(LIST_TABS[0]).toMatchObject({ key: 'finding', label: '찾는 중이에요' });
  });

  test('찾는 중은 missingperson, 보호 중은 protectedperson 을 부른다', async () => {
    global.fetch = serve(() => []);
    await fetchPersonCards('finding', '전체');
    await fetchPersonCards('protecting', '전체');
    expect(calledUrls()).toEqual([
      expect.stringMatching(/\/dasibom\/missingperson\/cards\/$/),
      expect.stringMatching(/\/dasibom\/protectedperson\/cards\/$/),
    ]);
  });

  test('경북은 경상북도로도 물어 합치고, 두 번 걸린 사람은 한 번만 최신 등록순으로', async () => {
    // "경상북도 문경시" 로 적힌 사람은 sido=경북 으로는 안 걸린다
    global.fetch = serve((url) => (url.includes('sido=경상북도')
      ? [card({ id: 554, name: '이춘자', registered_date: '2026-09-14' }), card()]
      : [card()]));
    const list = await fetchPersonCards('finding', '경북');
    expect(calledUrls()).toEqual([
      expect.stringContaining('?sido=경북'),
      expect.stringContaining('?sido=경상북도'),
    ]);
    expect(list.map(p => p.name)).toEqual(['이춘자', '진대덕']);
  });

  test('보호 중 등록일의 점 표기를 찾는 중과 같은 모양으로 맞춘다', async () => {
    global.fetch = serve(() => [card({ registered_date: '2026.03.17' })]);
    const [person] = await fetchPersonCards('protecting', '서울');
    expect(person.registeredDate).toBe('2026-03-17');
  });

  test('서버가 오류를 주면 "정보 없음" 으로 삼키지 않고 실패시킨다', async () => {
    global.fetch = jest.fn(async () => ({ ok: false, status: 500, json: async () => ({}) }));
    await expect(fetchPersonCards('finding', '전체')).rejects.toThrow('HTTP 500');
  });
});

describe('regionQueries - 주소에 적히는 이름으로 지역을 묻는다', () => {
  test('전체는 지역 필터 없이 한 번만', () => {
    expect(regionQueries('전체')).toEqual([null]);
  });

  test('약칭이 주소에 그대로 들어가는 지역은 약칭 하나로', () => {
    expect(regionQueries('서울')).toEqual(['서울']); // 서울특별시
    expect(regionQueries('강원')).toEqual(['강원']); // 강원도, 강원특별자치도
  });

  test('도 이름이 풀어서 적히는 지역은 정식 명칭도 같이', () => {
    [['충북', '충청북도'], ['충남', '충청남도'], ['경북', '경상북도'],
      ['경남', '경상남도'], ['전북', '전라북도'], ['전남', '전라남도']]
      .forEach(([short, full]) => expect(regionQueries(short)).toEqual([short, full]));
  });
});
