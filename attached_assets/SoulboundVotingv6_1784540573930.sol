// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// PINNED to 5.0.2 — later 5.x versions use the MCOPY opcode (Cancun hardfork),
// which SKALE's EVM does not fully support. Pinning avoids that class of bug.
import "@openzeppelin/contracts@5.0.2/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts@5.0.2/access/Ownable.sol";

/// @title SoulboundVoting v6 — Nationwide, multi-province edition
/// @notice Adds a full Province -> District -> City/Municipality -> Barangay
///         hierarchy and splits voting into two independent rounds:
///         NATIONAL_LOCAL (President down through City Councilor) and
///         BARANGAY (Barangay Captain + Kagawad), matching how Philippine
///         elections actually run barangay elections separately.
///         Voter geography is self-declared at the moment of voting (no
///         admin pre-registration step), matching the existing app design.
contract SoulboundVotingv6 is ERC721, Ownable {
    enum Round { NATIONAL_LOCAL, BARANGAY }

    enum Position {
        PRESIDENT,                  // 0  national
        VICE_PRESIDENT,              // 1  national
        SENATOR,                     // 2  national
        PARTY_LIST_REPRESENTATIVE,   // 3  national
        PROVINCIAL_GOVERNOR,         // 4  province-scoped
        PROVINCIAL_VICE_GOVERNOR,    // 5  province-scoped
        DISTRICT_REPRESENTATIVE,     // 6  district-scoped
        PROVINCIAL_BOARD_MEMBER,     // 7  district-scoped
        CITY_MAYOR,                  // 8  city-scoped
        CITY_VICE_MAYOR,             // 9  city-scoped
        CITY_COUNCILOR,              // 10 city-scoped
        BARANGAY_CAPTAIN,            // 11 barangay-scoped, Round.BARANGAY
        BARANGAY_KAGAWAD             // 12 barangay-scoped, Round.BARANGAY
    }

    uint8 private constant POSITION_COUNT = 13;

    struct Candidate {
        uint256 id;
        string name;
        string details;
        bool active;
    }

    struct Province {
        uint256 id;
        string name;
        bool exists;
    }

    struct District {
        uint256 id;
        string name;
        uint256 provinceId;
        bool exists;
    }

    struct CityMun {
        uint256 id;
        string name;
        uint256 districtId;
        bool exists;
    }

    struct Barangay {
        uint256 id;
        string name;
        uint256 cityId;
        bool exists;
    }

    struct PositionVote {
        Position position;
        uint256[] candidateIds;
    }

    // ============ GEOGRAPHY ============
    mapping(uint256 => Province) public provinces;
    uint256[] public provinceIds;
    uint256 private nextProvinceId = 1;

    mapping(uint256 => District) public districts;
    uint256[] public districtIds;
    uint256 private nextDistrictId = 1;
    // parent-scoped child index: lets duplicate-name checks and "has children"
    // checks run in O(children of THIS parent) instead of O(every district
    // nationwide) — critical at real scale (thousands of cities, ~42k barangays).
    mapping(uint256 => uint256[]) private districtsOfProvince;

    mapping(uint256 => CityMun) public cities;
    uint256[] public cityIds;
    uint256 private nextCityId = 1;
    mapping(uint256 => uint256[]) private citiesOfDistrict;

    mapping(uint256 => Barangay) public barangays;
    uint256[] public barangayIds;
    uint256 private nextBarangayId = 1;
    mapping(uint256 => uint256[]) private barangaysOfCity;

    // Blocks removing a city/barangay once real ballots were cast there.
    // Province/district removal is already blocked transitively — you can't
    // remove a province/district while it still has child cities/districts,
    // and you can't remove a city that has votes, so the chain is protected
    // without needing separate counters at every level.
    mapping(uint256 => uint256) public cityVoterCount;
    mapping(uint256 => uint256) public barangayVoterCount;

    // ============ CANDIDATES (unified: scopeId=0 means national) ============
    // scopeId meaning depends on Position: 0 = national, else provinceId /
    // districtId / cityId / barangayId as appropriate for that position.
    mapping(uint256 => mapping(Position => Candidate[])) private candidates;
    mapping(uint256 => mapping(Position => uint256)) private nextCandidateId;
    mapping(uint256 => mapping(Position => uint256)) private activeCandidateCount;
    // candidateId => (array index + 1); 0 means "not found"
    mapping(uint256 => mapping(Position => mapping(uint256 => uint256))) private candidateIndex;

    mapping(Position => uint8) public maxPicksPerPosition;
    mapping(uint256 => mapping(Position => mapping(uint256 => uint256))) public voteCounts;

    // ============ VOTING STATE (per round) ============
    mapping(Round => bool) public votingOpenFor;
    mapping(Round => mapping(address => bool)) public hasVotedInRound;
    mapping(address => uint256) public voterCityId;      // set after NATIONAL_LOCAL ballot
    mapping(address => uint256) public voterBarangayId;  // set after BARANGAY ballot
    uint256 private nextTokenId = 1;

    // ============ AUDIT: per-round ballot numbering ============
    // Each round has its own independent counter, so National/Local ballots
    // are numbered 1, 2, 3... and Barangay ballots are also numbered 1, 2, 3...
    // separately. This lets anyone publicly cross-check: sum of all candidate
    // vote counts for a position should never exceed totalBallotsInRound for
    // that position's round (accounting for maxPicks > 1 positions like
    // Senator or Councilor, where one ballot can contribute multiple votes).
    mapping(Round => uint256) public totalBallotsInRound;
    mapping(uint256 => Round) public tokenRound;         // which round each tokenId belongs to
    mapping(uint256 => uint256) public tokenBallotNumber; // sequence number within that round

    function getBallotInfo(uint256 tokenId) external view returns (Round round, uint256 ballotNumber) {
        return (tokenRound[tokenId], tokenBallotNumber[tokenId]);
    }

    // ============ EVENTS ============
    event ProvinceAdded(uint256 indexed provinceId, string name);
    event ProvinceRemoved(uint256 indexed provinceId, string name);
    event DistrictAdded(uint256 indexed districtId, uint256 indexed provinceId, string name);
    event DistrictRemoved(uint256 indexed districtId, string name);
    event CityAdded(uint256 indexed cityId, uint256 indexed districtId, string name);
    event CityRemoved(uint256 indexed cityId, string name);
    event BarangayAdded(uint256 indexed barangayId, uint256 indexed cityId, string name);
    event BarangayRemoved(uint256 indexed barangayId, string name);
    event CandidateAdded(Position indexed position, uint256 indexed scopeId, uint256 candidateId, string name);
    event CandidateRemoved(Position indexed position, uint256 indexed scopeId, uint256 candidateId);
    event VotingOpened(Round round);
    event VotingClosed(Round round);
    event BallotCast(address indexed voter, Round round, uint256 indexed tokenId);

    // ============ ERRORS ============
    error VotingNotOpen();
    error VotingIsOpen();
    error AlreadyVoted();
    error WrongRoundForPosition();
    error InvalidProvince();
    error InvalidDistrict();
    error InvalidCity();
    error InvalidBarangay();
    error MismatchedHierarchy();
    error ProvinceHasChildren();
    error DistrictHasChildren();
    error CityHasChildren();
    error CityHasVoters();
    error BarangayHasVoters();
    error DuplicatePosition();
    error BatchTooLarge();
    error ProvinceNotFound();
    error DistrictNotFound();
    error CityNotFound();
    error BarangayNotFound();
    error DuplicateName();
    error InvalidCandidate();
    error PositionNotAllowedForLevel();
    error TooManyPicks();
    error DuplicatePick();
    error MaxMustBePositive();
    error EmptyName();

    constructor() ERC721("VoterReceipt", "VOTE") Ownable(msg.sender) {
        maxPicksPerPosition[Position.PRESIDENT] = 1;
        maxPicksPerPosition[Position.VICE_PRESIDENT] = 1;
        maxPicksPerPosition[Position.SENATOR] = 12;
        maxPicksPerPosition[Position.PARTY_LIST_REPRESENTATIVE] = 1;
        maxPicksPerPosition[Position.PROVINCIAL_GOVERNOR] = 1;
        maxPicksPerPosition[Position.PROVINCIAL_VICE_GOVERNOR] = 1;
        maxPicksPerPosition[Position.DISTRICT_REPRESENTATIVE] = 1;
        maxPicksPerPosition[Position.PROVINCIAL_BOARD_MEMBER] = 6;
        maxPicksPerPosition[Position.CITY_MAYOR] = 1;
        maxPicksPerPosition[Position.CITY_VICE_MAYOR] = 1;
        maxPicksPerPosition[Position.CITY_COUNCILOR] = 8;
        maxPicksPerPosition[Position.BARANGAY_CAPTAIN] = 1;
        maxPicksPerPosition[Position.BARANGAY_KAGAWAD] = 7;
    }

    modifier onlyBeforeVoting(Round round) {
        if (votingOpenFor[round]) revert VotingIsOpen();
        _;
    }

    // ============ POSITION HELPERS ============
    function _isNational(Position p) private pure returns (bool) {
        return p == Position.PRESIDENT || p == Position.VICE_PRESIDENT ||
               p == Position.SENATOR || p == Position.PARTY_LIST_REPRESENTATIVE;
    }
    function _isProvincePosition(Position p) private pure returns (bool) {
        return p == Position.PROVINCIAL_GOVERNOR || p == Position.PROVINCIAL_VICE_GOVERNOR;
    }
    function _isDistrictPosition(Position p) private pure returns (bool) {
        return p == Position.DISTRICT_REPRESENTATIVE || p == Position.PROVINCIAL_BOARD_MEMBER;
    }
    function _isCityPosition(Position p) private pure returns (bool) {
        return p == Position.CITY_MAYOR || p == Position.CITY_VICE_MAYOR || p == Position.CITY_COUNCILOR;
    }
    function _isBarangayPosition(Position p) private pure returns (bool) {
        return p == Position.BARANGAY_CAPTAIN || p == Position.BARANGAY_KAGAWAD;
    }
    function _roundOf(Position p) private pure returns (Round) {
        return _isBarangayPosition(p) ? Round.BARANGAY : Round.NATIONAL_LOCAL;
    }

    // ============ VIEW: GEOGRAPHY ============
    // getProvinces()/getDistricts() stay flat+unpaginated — nationwide counts
    // for these are small (~82 provinces, ~250 districts) and safe in one call.
    function getProvinces() external view returns (Province[] memory) {
        Province[] memory out = new Province[](provinceIds.length);
        for (uint256 i = 0; i < provinceIds.length; i++) out[i] = provinces[provinceIds[i]];
        return out;
    }
    function getDistricts() external view returns (District[] memory) {
        District[] memory out = new District[](districtIds.length);
        for (uint256 i = 0; i < districtIds.length; i++) out[i] = districts[districtIds[i]];
        return out;
    }

    // getCities()/getBarangays() below are kept for small/test datasets, but
    // MUST NOT be called by the frontend once real nationwide data is loaded
    // (~1,634 cities, ~42,000 barangays) — a single eth_call returning that
    // much data risks the same empty-response failure mode this project hit
    // earlier from an unrelated compiler bug. Use the scoped/paginated
    // versions below instead for any real deployment.
    function getCities() external view returns (CityMun[] memory) {
        CityMun[] memory out = new CityMun[](cityIds.length);
        for (uint256 i = 0; i < cityIds.length; i++) out[i] = cities[cityIds[i]];
        return out;
    }
    function getBarangays() external view returns (Barangay[] memory) {
        Barangay[] memory out = new Barangay[](barangayIds.length);
        for (uint256 i = 0; i < barangayIds.length; i++) out[i] = barangays[barangayIds[i]];
        return out;
    }

    // --- Scoped getters (recommended default for cascading selection UIs) ---
    function getDistrictsOfProvince(uint256 provinceId) external view returns (District[] memory) {
        uint256[] storage ids = districtsOfProvince[provinceId];
        District[] memory out = new District[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) out[i] = districts[ids[i]];
        return out;
    }
    function getCitiesOfDistrict(uint256 districtId) external view returns (CityMun[] memory) {
        uint256[] storage ids = citiesOfDistrict[districtId];
        CityMun[] memory out = new CityMun[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) out[i] = cities[ids[i]];
        return out;
    }

    // --- Scoped + paginated (recommended for barangays — a single city can
    // have 100+ barangays, and this keeps every response small regardless
    // of how large that city's list grows) ---
    function getBarangaysOfCityPaginated(uint256 cityId, uint256 offset, uint256 limit)
        external view returns (Barangay[] memory page, uint256 total)
    {
        uint256[] storage ids = barangaysOfCity[cityId];
        total = ids.length;
        if (offset >= total) return (new Barangay[](0), total);
        uint256 end = offset + limit;
        if (end > total) end = total;
        page = new Barangay[](end - offset);
        for (uint256 i = offset; i < end; i++) page[i - offset] = barangays[ids[i]];
        return (page, total);
    }

    // --- Flat + paginated (admin "browse everything" / cross-country search
    // fallback only — cascading scoped queries above should be the default
    // path for normal voter-facing UI) ---
    function getCitiesPaginated(uint256 offset, uint256 limit)
        external view returns (CityMun[] memory page, uint256 total)
    {
        total = cityIds.length;
        if (offset >= total) return (new CityMun[](0), total);
        uint256 end = offset + limit;
        if (end > total) end = total;
        page = new CityMun[](end - offset);
        for (uint256 i = offset; i < end; i++) page[i - offset] = cities[cityIds[i]];
        return (page, total);
    }
    function getBarangaysPaginated(uint256 offset, uint256 limit)
        external view returns (Barangay[] memory page, uint256 total)
    {
        total = barangayIds.length;
        if (offset >= total) return (new Barangay[](0), total);
        uint256 end = offset + limit;
        if (end > total) end = total;
        page = new Barangay[](end - offset);
        for (uint256 i = offset; i < end; i++) page[i - offset] = barangays[barangayIds[i]];
        return (page, total);
    }

    // ============ VIEW: CANDIDATES (explicit wrappers per level) ============
    function getNationalCandidates(Position position) external view returns (Candidate[] memory) {
        return candidates[0][position];
    }
    function getProvincialCandidates(uint256 provinceId, Position position) external view returns (Candidate[] memory) {
        return candidates[provinceId][position];
    }
    function getDistrictCandidates(uint256 districtId, Position position) external view returns (Candidate[] memory) {
        return candidates[districtId][position];
    }
    function getCityCandidates(uint256 cityId, Position position) external view returns (Candidate[] memory) {
        return candidates[cityId][position];
    }
    function getBarangayCandidates(uint256 barangayId, Position position) external view returns (Candidate[] memory) {
        return candidates[barangayId][position];
    }

    function getAllPositions() external pure returns (Position[] memory) {
        Position[] memory all = new Position[](POSITION_COUNT);
        for (uint8 i = 0; i < POSITION_COUNT; i++) all[i] = Position(i);
        return all;
    }

    function positionName(Position position) external pure returns (string memory) {
        if (position == Position.PRESIDENT) return "President";
        if (position == Position.VICE_PRESIDENT) return "Vice President";
        if (position == Position.SENATOR) return "Senator";
        if (position == Position.PARTY_LIST_REPRESENTATIVE) return "Party-List Representative";
        if (position == Position.PROVINCIAL_GOVERNOR) return "Provincial Governor";
        if (position == Position.PROVINCIAL_VICE_GOVERNOR) return "Provincial Vice Governor";
        if (position == Position.DISTRICT_REPRESENTATIVE) return "District Representative";
        if (position == Position.PROVINCIAL_BOARD_MEMBER) return "Provincial Board Member";
        if (position == Position.CITY_MAYOR) return "City / Municipal Mayor";
        if (position == Position.CITY_VICE_MAYOR) return "City / Municipal Vice Mayor";
        if (position == Position.CITY_COUNCILOR) return "City / Municipal Councilor";
        if (position == Position.BARANGAY_CAPTAIN) return "Barangay Captain";
        return "Barangay Kagawad";
    }

    function getVoteCount(uint256 scopeId, Position position, uint256 candidateId) external view returns (uint256) {
        return voteCounts[scopeId][position][candidateId];
    }

    // ============ ADMIN: GEOGRAPHY ============
    uint256 private constant MAX_BATCH_SIZE = 100;

    function _addProvince(string calldata name) private returns (uint256) {
        if (bytes(name).length == 0) revert EmptyName();
        for (uint256 i = 0; i < provinceIds.length; i++) {
            if (keccak256(bytes(provinces[provinceIds[i]].name)) == keccak256(bytes(name))) revert DuplicateName();
        }
        uint256 id = nextProvinceId++;
        provinces[id] = Province({id: id, name: name, exists: true});
        provinceIds.push(id);
        emit ProvinceAdded(id, name);
        return id;
    }

    function addProvince(string calldata name) external onlyOwner returns (uint256) {
        return _addProvince(name);
    }

    function addProvincesBatch(string[] calldata names) external onlyOwner returns (uint256[] memory ids) {
        if (names.length == 0 || names.length > MAX_BATCH_SIZE) revert BatchTooLarge();
        ids = new uint256[](names.length);
        for (uint256 i = 0; i < names.length; i++) ids[i] = _addProvince(names[i]);
        return ids;
    }

    function _addDistrict(string calldata name, uint256 provinceId) private returns (uint256) {
        if (bytes(name).length == 0) revert EmptyName();
        if (!provinces[provinceId].exists) revert InvalidProvince();
        uint256[] storage siblings = districtsOfProvince[provinceId];
        for (uint256 i = 0; i < siblings.length; i++) {
            District storage d = districts[siblings[i]];
            if (d.exists && keccak256(bytes(d.name)) == keccak256(bytes(name))) revert DuplicateName();
        }
        uint256 id = nextDistrictId++;
        districts[id] = District({id: id, name: name, provinceId: provinceId, exists: true});
        districtIds.push(id);
        districtsOfProvince[provinceId].push(id);
        emit DistrictAdded(id, provinceId, name);
        return id;
    }

    function addDistrict(string calldata name, uint256 provinceId) external onlyOwner returns (uint256) {
        return _addDistrict(name, provinceId);
    }

    function addDistrictsBatch(string[] calldata names, uint256 provinceId) external onlyOwner returns (uint256[] memory ids) {
        if (names.length == 0 || names.length > MAX_BATCH_SIZE) revert BatchTooLarge();
        ids = new uint256[](names.length);
        for (uint256 i = 0; i < names.length; i++) ids[i] = _addDistrict(names[i], provinceId);
        return ids;
    }

    function _addCity(string calldata name, uint256 districtId) private returns (uint256) {
        if (bytes(name).length == 0) revert EmptyName();
        if (!districts[districtId].exists) revert InvalidDistrict();
        uint256[] storage siblings = citiesOfDistrict[districtId];
        for (uint256 i = 0; i < siblings.length; i++) {
            CityMun storage c = cities[siblings[i]];
            if (c.exists && keccak256(bytes(c.name)) == keccak256(bytes(name))) revert DuplicateName();
        }
        uint256 id = nextCityId++;
        cities[id] = CityMun({id: id, name: name, districtId: districtId, exists: true});
        cityIds.push(id);
        citiesOfDistrict[districtId].push(id);
        emit CityAdded(id, districtId, name);
        return id;
    }

    function addCity(string calldata name, uint256 districtId) external onlyOwner returns (uint256) {
        return _addCity(name, districtId);
    }

    function addCitiesBatch(string[] calldata names, uint256 districtId) external onlyOwner returns (uint256[] memory ids) {
        if (names.length == 0 || names.length > MAX_BATCH_SIZE) revert BatchTooLarge();
        ids = new uint256[](names.length);
        for (uint256 i = 0; i < names.length; i++) ids[i] = _addCity(names[i], districtId);
        return ids;
    }

    function _addBarangay(string calldata name, uint256 cityId) private returns (uint256) {
        if (bytes(name).length == 0) revert EmptyName();
        if (!cities[cityId].exists) revert InvalidCity();
        uint256[] storage siblings = barangaysOfCity[cityId];
        for (uint256 i = 0; i < siblings.length; i++) {
            Barangay storage b = barangays[siblings[i]];
            if (b.exists && keccak256(bytes(b.name)) == keccak256(bytes(name))) revert DuplicateName();
        }
        uint256 id = nextBarangayId++;
        barangays[id] = Barangay({id: id, name: name, cityId: cityId, exists: true});
        barangayIds.push(id);
        barangaysOfCity[cityId].push(id);
        emit BarangayAdded(id, cityId, name);
        return id;
    }

    function addBarangay(string calldata name, uint256 cityId) external onlyOwner returns (uint256) {
        return _addBarangay(name, cityId);
    }

    function addBarangaysBatch(string[] calldata names, uint256 cityId) external onlyOwner returns (uint256[] memory ids) {
        if (names.length == 0 || names.length > MAX_BATCH_SIZE) revert BatchTooLarge();
        ids = new uint256[](names.length);
        for (uint256 i = 0; i < names.length; i++) ids[i] = _addBarangay(names[i], cityId);
        return ids;
    }

    function removeProvince(uint256 provinceId) external onlyOwner {
        if (!provinces[provinceId].exists) revert ProvinceNotFound();
        uint256[] storage children = districtsOfProvince[provinceId];
        for (uint256 i = 0; i < children.length; i++) {
            if (districts[children[i]].exists) revert ProvinceHasChildren();
        }
        string memory name = provinces[provinceId].name;
        provinces[provinceId].exists = false;
        _removeFromArray(provinceIds, provinceId);
        emit ProvinceRemoved(provinceId, name);
    }

    function removeDistrict(uint256 districtId) external onlyOwner {
        if (!districts[districtId].exists) revert DistrictNotFound();
        uint256[] storage children = citiesOfDistrict[districtId];
        for (uint256 i = 0; i < children.length; i++) {
            if (cities[children[i]].exists) revert DistrictHasChildren();
        }
        string memory name = districts[districtId].name;
        uint256 provinceId = districts[districtId].provinceId;
        districts[districtId].exists = false;
        _removeFromArray(districtIds, districtId);
        _removeFromArray(districtsOfProvince[provinceId], districtId);
        emit DistrictRemoved(districtId, name);
    }

    function removeCity(uint256 cityId) external onlyOwner {
        if (!cities[cityId].exists) revert CityNotFound();
        if (cityVoterCount[cityId] > 0) revert CityHasVoters();
        uint256[] storage children = barangaysOfCity[cityId];
        for (uint256 i = 0; i < children.length; i++) {
            if (barangays[children[i]].exists) revert CityHasChildren();
        }
        string memory name = cities[cityId].name;
        uint256 districtId = cities[cityId].districtId;
        cities[cityId].exists = false;
        _removeFromArray(cityIds, cityId);
        _removeFromArray(citiesOfDistrict[districtId], cityId);
        emit CityRemoved(cityId, name);
    }

    function removeBarangay(uint256 barangayId) external onlyOwner {
        if (!barangays[barangayId].exists) revert BarangayNotFound();
        if (barangayVoterCount[barangayId] > 0) revert BarangayHasVoters();
        string memory name = barangays[barangayId].name;
        uint256 cityId = barangays[barangayId].cityId;
        barangays[barangayId].exists = false;
        _removeFromArray(barangayIds, barangayId);
        _removeFromArray(barangaysOfCity[cityId], barangayId);
        emit BarangayRemoved(barangayId, name);
    }

    function _removeFromArray(uint256[] storage arr, uint256 val) private {
        uint256 len = arr.length;
        for (uint256 i = 0; i < len; i++) {
            if (arr[i] == val) {
                arr[i] = arr[len - 1];
                arr.pop();
                break;
            }
        }
    }

    // ============ ADMIN: CANDIDATES ============
    function _addCandidate(uint256 scopeId, Position position, string calldata name, string calldata details) private returns (uint256) {
        if (bytes(name).length == 0) revert EmptyName();
        uint256 id = nextCandidateId[scopeId][position]++;
        candidates[scopeId][position].push(Candidate({id: id, name: name, details: details, active: true}));
        candidateIndex[scopeId][position][id] = candidates[scopeId][position].length;
        activeCandidateCount[scopeId][position]++;
        emit CandidateAdded(position, scopeId, id, name);
        return id;
    }

    function _removeCandidate(uint256 scopeId, Position position, uint256 candidateId) private {
        uint256 idxPlusOne = candidateIndex[scopeId][position][candidateId];
        if (idxPlusOne == 0) revert InvalidCandidate();
        Candidate storage cand = candidates[scopeId][position][idxPlusOne - 1];
        if (cand.active) {
            cand.active = false;
            activeCandidateCount[scopeId][position]--;
        }
        emit CandidateRemoved(position, scopeId, candidateId);
    }

    function addNationalCandidate(Position position, string calldata name, string calldata details)
        external onlyOwner onlyBeforeVoting(Round.NATIONAL_LOCAL) returns (uint256)
    {
        if (!_isNational(position)) revert PositionNotAllowedForLevel();
        return _addCandidate(0, position, name, details);
    }

    function addProvincialCandidate(uint256 provinceId, Position position, string calldata name, string calldata details)
        external onlyOwner onlyBeforeVoting(Round.NATIONAL_LOCAL) returns (uint256)
    {
        if (!_isProvincePosition(position)) revert PositionNotAllowedForLevel();
        if (!provinces[provinceId].exists) revert InvalidProvince();
        return _addCandidate(provinceId, position, name, details);
    }

    function addDistrictCandidate(uint256 districtId, Position position, string calldata name, string calldata details)
        external onlyOwner onlyBeforeVoting(Round.NATIONAL_LOCAL) returns (uint256)
    {
        if (!_isDistrictPosition(position)) revert PositionNotAllowedForLevel();
        if (!districts[districtId].exists) revert InvalidDistrict();
        return _addCandidate(districtId, position, name, details);
    }

    function addCityCandidate(uint256 cityId, Position position, string calldata name, string calldata details)
        external onlyOwner onlyBeforeVoting(Round.NATIONAL_LOCAL) returns (uint256)
    {
        if (!_isCityPosition(position)) revert PositionNotAllowedForLevel();
        if (!cities[cityId].exists) revert InvalidCity();
        return _addCandidate(cityId, position, name, details);
    }

    function addBarangayCandidate(uint256 barangayId, Position position, string calldata name, string calldata details)
        external onlyOwner onlyBeforeVoting(Round.BARANGAY) returns (uint256)
    {
        if (!_isBarangayPosition(position)) revert PositionNotAllowedForLevel();
        if (!barangays[barangayId].exists) revert InvalidBarangay();
        return _addCandidate(barangayId, position, name, details);
    }

    function removeNationalCandidate(Position position, uint256 candidateId) external onlyOwner onlyBeforeVoting(Round.NATIONAL_LOCAL) {
        _removeCandidate(0, position, candidateId);
    }
    function removeProvincialCandidate(uint256 provinceId, Position position, uint256 candidateId) external onlyOwner onlyBeforeVoting(Round.NATIONAL_LOCAL) {
        _removeCandidate(provinceId, position, candidateId);
    }
    function removeDistrictCandidate(uint256 districtId, Position position, uint256 candidateId) external onlyOwner onlyBeforeVoting(Round.NATIONAL_LOCAL) {
        _removeCandidate(districtId, position, candidateId);
    }
    function removeCityCandidate(uint256 cityId, Position position, uint256 candidateId) external onlyOwner onlyBeforeVoting(Round.NATIONAL_LOCAL) {
        _removeCandidate(cityId, position, candidateId);
    }
    function removeBarangayCandidate(uint256 barangayId, Position position, uint256 candidateId) external onlyOwner onlyBeforeVoting(Round.BARANGAY) {
        _removeCandidate(barangayId, position, candidateId);
    }

    function setMaxPicks(Position position, uint8 max) external onlyOwner {
        if (max == 0) revert MaxMustBePositive();
        if (votingOpenFor[_roundOf(position)]) revert VotingIsOpen();
        maxPicksPerPosition[position] = max;
    }

    // ============ ADMIN: VOTING CONTROL ============
    function openVoting(Round round) external onlyOwner {
        votingOpenFor[round] = true;
        emit VotingOpened(round);
    }
    function closeVoting(Round round) external onlyOwner {
        votingOpenFor[round] = false;
        emit VotingClosed(round);
    }

    // ============ VOTING ============
    function castNationalLocalBallot(uint256 provinceId, uint256 districtId, uint256 cityId, PositionVote[] calldata votes) external {
        if (!votingOpenFor[Round.NATIONAL_LOCAL]) revert VotingNotOpen();
        if (hasVotedInRound[Round.NATIONAL_LOCAL][msg.sender]) revert AlreadyVoted();
        if (!provinces[provinceId].exists) revert InvalidProvince();
        if (!districts[districtId].exists || districts[districtId].provinceId != provinceId) revert MismatchedHierarchy();
        if (!cities[cityId].exists || cities[cityId].districtId != districtId) revert MismatchedHierarchy();

        uint16 seenPositions = 0;
        for (uint256 v = 0; v < votes.length; v++) {
            Position position = votes[v].position;
            if (_isBarangayPosition(position)) revert WrongRoundForPosition();

            uint16 bit = uint16(1) << uint8(position);
            if (seenPositions & bit != 0) revert DuplicatePosition();
            seenPositions |= bit;

            uint256 scopeId = 0;
            if (_isProvincePosition(position)) scopeId = provinceId;
            else if (_isDistrictPosition(position)) scopeId = districtId;
            else if (_isCityPosition(position)) scopeId = cityId;
            // else national: scopeId stays 0

            _tallyVotes(scopeId, position, votes[v].candidateIds);
        }

        hasVotedInRound[Round.NATIONAL_LOCAL][msg.sender] = true;
        voterCityId[msg.sender] = cityId;
        cityVoterCount[cityId]++;
        uint256 tokenId = nextTokenId++;
        uint256 ballotNumber = ++totalBallotsInRound[Round.NATIONAL_LOCAL];
        tokenRound[tokenId] = Round.NATIONAL_LOCAL;
        tokenBallotNumber[tokenId] = ballotNumber;
        _safeMint(msg.sender, tokenId);
        emit BallotCast(msg.sender, Round.NATIONAL_LOCAL, tokenId);
    }

    function castBarangayBallot(uint256 barangayId, PositionVote[] calldata votes) external {
        if (!votingOpenFor[Round.BARANGAY]) revert VotingNotOpen();
        if (hasVotedInRound[Round.BARANGAY][msg.sender]) revert AlreadyVoted();
        if (!barangays[barangayId].exists) revert InvalidBarangay();

        uint16 seenPositions = 0;
        for (uint256 v = 0; v < votes.length; v++) {
            Position position = votes[v].position;
            if (!_isBarangayPosition(position)) revert WrongRoundForPosition();

            uint16 bit = uint16(1) << uint8(position);
            if (seenPositions & bit != 0) revert DuplicatePosition();
            seenPositions |= bit;

            _tallyVotes(barangayId, position, votes[v].candidateIds);
        }

        hasVotedInRound[Round.BARANGAY][msg.sender] = true;
        voterBarangayId[msg.sender] = barangayId;
        barangayVoterCount[barangayId]++;
        uint256 tokenId = nextTokenId++;
        uint256 ballotNumber = ++totalBallotsInRound[Round.BARANGAY];
        tokenRound[tokenId] = Round.BARANGAY;
        tokenBallotNumber[tokenId] = ballotNumber;
        _safeMint(msg.sender, tokenId);
        emit BallotCast(msg.sender, Round.BARANGAY, tokenId);
    }

    function _tallyVotes(uint256 scopeId, Position position, uint256[] calldata picks) private {
        uint8 max = maxPicksPerPosition[position];
        if (picks.length > max) revert TooManyPicks();

        for (uint256 i = 0; i < picks.length; i++) {
            for (uint256 j = i + 1; j < picks.length; j++) {
                if (picks[i] == picks[j]) revert DuplicatePick();
            }
        }

        for (uint256 i = 0; i < picks.length; i++) {
            uint256 candidateId = picks[i];
            uint256 idxPlusOne = candidateIndex[scopeId][position][candidateId];
            if (idxPlusOne == 0 || !candidates[scopeId][position][idxPlusOne - 1].active) revert InvalidCandidate();
            voteCounts[scopeId][position][candidateId] += 1;
        }
    }

    // ============ SOULBOUND ============
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert("This is a Soulbound receipt and cannot be transferred.");
        }
        return super._update(to, tokenId, auth);
    }
}
