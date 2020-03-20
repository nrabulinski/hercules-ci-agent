{ mkDerivation
, aeson
, async
, base
, bytestring
, conduit
, conduit-extra
, containers
, cookie
, directory
, filepath
, hercules-ci-api-agent
, hercules-ci-api-core
, hspec
, http-api-data
, mmorph
, protolude
, random
, safe-exceptions
, servant
, servant-auth-server
, servant-conduit
, servant-server
, servant-websockets
, stdenv
, stm
, tar-conduit
, text
, uuid
, warp
, websockets
}:
mkDerivation {
  pname = "hercules-ci-agent-test";
  version = "0.1.0.0";
  src = tests/agent-test;
  isLibrary = false;
  isExecutable = true;
  executableHaskellDepends = [
    aeson
    async
    base
    bytestring
    conduit
    conduit-extra
    containers
    cookie
    directory
    filepath
    hercules-ci-api-agent
    hercules-ci-api-core
    hspec
    http-api-data
    mmorph
    protolude
    random
    safe-exceptions
    servant
    servant-auth-server
    servant-conduit
    servant-server
    servant-websockets
    stm
    tar-conduit
    text
    uuid
    warp
    websockets
  ];
  homepage = "https://github.com/hercules-ci/hercules-ci#readme";
  license = stdenv.lib.licenses.asl20;
}
