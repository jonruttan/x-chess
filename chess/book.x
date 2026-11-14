; # x-chess -- a chess engine on x-lang
;
; ## chess/book.x -- opening books
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Before it searches, the engine looks the position up in a book and,
; when the book knows it, plays one of the book's moves, drawn at random
; by their weights.  A book is the symbol builtin, the main lines below,
; or the path of a Polyglot .bin file, the format most opening books are
; shipped in; () is no book.
;
; A Polyglot file is a run of 16-byte entries sorted by key: the
; position's key in 8 bytes, the move in 2, its weight in 2 and 4 bytes
; a book maker may use, all big-endian.  The key is a Zobrist hash: the
; exclusive or of one of 781 published 64-bit numbers for each piece on
; its square, each castling right, the en passant file when a pawn can
; take there, and white to move.  The numbers are held here as four
; 16-bit limbs each, so the hash is the same on an engine of any word
; width.

(module chess/book)

(import x/sys/gc)
(import x/sys/file)
(import x/core/doors int+ int- int* int/ int< int= int& int| int<< int>> obj-ref obj-set!
  str-make str-byte-ref str-byte-len str-byte-sub)
(import chess/board fen-start pos-from-fen pos-piece pos-side pos-castle pos-ep pos-key
  sq-parse move-from move-to move-promo gen-moves make! unmake! chess-roll)

(def %xor (prim-ref (lit int) (lit ^)))

; --- the Zobrist numbers ------------------------------------------------------
;
; Polyglot's 781 numbers in hex, four to a line: 0 to 767 a piece on a
; square, at 64 times the piece's index (black pawn 0, white pawn 1, and
; so on to white king 11) plus the square, a1 0 to h8 63; 768 to 771
; the castling rights K Q k q; 772 to 779 the en passant file; 780
; white to move.
(def %hex
  (list
    "9d39247e33776d412af7398005aaa5c744db0150246235479c15f73e62a76ae2"
    "75834465489c0c893290ac3a203001bf0fbbad1f61042279e83a908ff2fb60ca"
    "0d7e765d58755c101a083822ceafe02d9605d5f0e25ec3b0d021ff5cd13a2ed5"
    "40bdf15d4a672e32011355146fd563955db4832046f3d9e5239f8b2d7ff719cc"
    "05d1a1ae85b49aa1679f848f6e8fc9717449bbff801fed0b7d11cdb1c3b7adf0"
    "82c7709e781eb7ccf3218f1c9510786c331478f3af51bbe64bb38de5e7219443"
    "aa649c6ebcfd50fc8dbd98a352afd40b87d2074b81d7921719f3c751d3e92ae1"
    "b4ab30f062b19abf7b0500ac42047ac4c9452ca81a09d85d24aa6c514da27500"
    "4c9f34427501b44714a68fd73c910841a71b9b83461cbd9303488b95b0f1850f"
    "637b2b34ff93c04009d1bc9a3dd90a943575668334a1dd3b735e2b97a4c45a23"
    "18727070f1bd400b1fcbacd259bf02e7d310a7c2ce9b6555bf983fe0fe5d8244"
    "9f74d14f7454a82451ebdc4ab9ba30355c82c505db9ab0fafcf7fe8a3430b241"
    "3253a729b9ba3dde8c74c368081b3075b9bc6c87167c33e77ef48f2b83024e20"
    "11d505d4c351bd7f6568fca92c76a2434de0b0f40f32a7b896d693460cc37e5d"
    "42e240cb63689f2f6d2bdcdae291966142880b0236e4d9515f0f4a5898171bb6"
    "39f890f579f92f8893c5b5f47356388b63dc359d8d231b78ec16ca8aea98ad76"
    "5355f900c2a82dc707fb9f855a9971425093417aa8a7ed5e7bcbc38da25a7f3c"
    "19fc8a768cf4b6d4637a7780decfc0d98249a47aee0e41f779ad695501e7d1e8"
    "14acbaf4777d5776f145b6beccdea195dabf2ac8201752fc24c3c94df9c8d3f6"
    "bb6e2924f03912ea0ce26c0b95c980d9a49cd132bfbf7cc4e99d662af4243939"
    "27e6ad7891165c3f8535f040b9744ff154b3f4fa5f40d87372b12c32127fed2b"
    "ee954d3c7b411f479a85ac909a24eaa170ac4cd9f04f21f5f9b89d3e99a075c2"
    "87b3e2b2b5c907b1a366e5b8c54f48b8ae4a9346cc3f7cf21920c04d47267bbd"
    "87bf02c6b49e2ae9092237ac237f3859ff07f64ef8ed14d08de8dca9f03cc54e"
    "9c1633264db49c89b3f22c3d0b0b38ed390e5fb44d01144b5bfea5b4712768e9"
    "1e1032911fa789849a74acb964e78cb34f80f7a035dafb046304d09a0b3738c4"
    "2171e64683023a085b9b63eb9ceff80c506aacf4898893421881afc9a3a701d6"
    "6503080440750644dfd395339cdbf4a7ef927dbcf00c20f27b32f7d1e03680ec"
    "b9fd7620e731624305a7e8a57db91b77b5889c6e15630a754a750a09ce9573f7"
    "cf464cec899a2f8af538639ce705b8243c79a0ff5580ef7fede6c87f8477609d"
    "799e81f05bc93f3186536b8cf3428a8c97d7374c60087b73a246637cff328532"
    "043fcae60cc0eba0920e449535dd359e70eb093b15b290cc73a1921916591cbd"
    "56436c9fe1a1aa8defac4b70633b8f81bb215798d45df7af45f20042f24f1768"
    "930f80f4e8eb7462ff6712ffcfd75ea1ae623fd67468aa70dd2c5bc84bc8d8fc"
    "7eed120d54cf2dd922fe545401165f1cc91800e98fb99929808bd68e6ac10365"
    "dec468145b7605f61bede3a3aef5330243539603d6c55602aa969b5c691ccb7a"
    "a87832d392efee5665942c7b3c7e11aeded2d633cad004f621f08570f420e565"
    "b415938d7da94e3c91b859e59ecb635010cff333e0ed804a28aed140be0bb7dd"
    "c5cc1d89724fa4565648f680f11a27412d255069f0b7dab39bc5a38ef729abd4"
    "ef2f054308f6a2bcaf2042f5cc5c2858480412bab7f5be2aaef3af4a563dfe43"
    "19afe59ae451497f52593803dff1e840f4f076e65f2ce6f011379625747d5af3"
    "bce5d2248682c1159da4243de836994f066f70b33fe090174dc4de189b671a1c"
    "51039ab7712457c3c07a3f80c31fb4b4b46ee9c5e64a6e7cb3819a42abe61c87"
    "21a007933a522a202df16f761598aa4f763c4a1371b368fdf793c46702e086a0"
    "d7288e012aeb8d31de336a2a4bc1c44b0bf692b38d079f232c604a7a177326b3"
    "4850e73e03eb6064cfc447f1e53c8e1bb05ca3f564268d999ae182c8bc9474e8"
    "a4fc4bd4fc5558cae755178d58fc4e7669b97db1a4c03dfef9b5b7c4acc67c96"
    "fc6a82d64b8655fb9c684cb6c4d244178ec97d2917456ed06703df9d2924e97e"
    "c547f57e42a7444e78e37644e7cad29efe9a44e9362f05fa08bd35cc38336615"
    "9315e5eb3a129ace94061b871e04df75df1d9f9d784ba0103bba57b68871b59d"
    "d2b7adeeded1f73ff7a255d83bc373f8d7f4f2448c0ceb81d95be88cd210ffa7"
    "336f52f8ff4728e7a74049dac312ac71a2f61bb6e437fdb54f2a5cb07f6a35b3"
    "87d380bda5bf785916b9f7e06c453a217ba2484c8a0fd54ef3a678cad9a2e38c"
    "39b0bf7dde437ba2fcaf55c1bf8a442418fcf680573fa5944c0563b89f495ac3"
    "40e087931a00930d8cffa9412eb642c168ca39053261169f7a1ee967d27579e2"
    "9d1d60e5076f5b6f3810e399b6f65ba232095b6d4ab5f9b135cab62109dd038a"
    "a90b24499fcfafb177a225a07cc2c6bd513e5e634c70e3314361c0ca3f692f12"
    "d941aca44b20a45b528f7c8602c5807b52ab92beb96139899d1dfa2efc557f73"
    "722ff175f572c3481d1260a51107fe977a249a57ec0c9ba204208fe9e8f7f2d6"
    "5a110c6058b920a00cd9a497658a569856fd23c8f9715a4c284c847b9d887aae"
    "04feabfbbdb619cb742e1e651c60ba839a9632e65904ad3c881b82a13b51b9e2"
    "506e6744cd974924b0183db56ffc6a790ed9b915c66ed37e5e11e86d5873d484"
    "f678647e3519ac6e1b85d488d0f20cc5dab9fe6525d890210d151d86adb73615"
    "a865a54edcc0f01993c42566aef98ffb99e7afeabe00073148cbff086ddf285a"
    "7f9b6af1ebf78baf58627e1a149bba212cd16e2abd791e33d363eff5f0977996"
    "0ce2a38c344a6eed1a804aadb9cfa741907f30421d78c5de501f65edb3034d07"
    "37624ae5a48fa6e9957baf61700cff4e3a6c27934e31188ad49503536abca345"
    "088e049589c432e0f943aee7febf21b86c3b8e3e336139d3364f6ffa464ee52e"
    "d60f6dcedc31422256963b0dca418fc016f50edf91e513afef1955914b609f93"
    "565601c0364e3228ecb53939887e8175bac7a9a18531294bb344c470397bba52"
    "65d34954daf3cebdb4b81b3fa97511e2b422061193d6f6a7071582401c38434d"
    "7a13f18bbedc4ff5bc4097b116c524d259b97885e2f2ea2899170a5dc3115544"
    "6f423357e7c6a9f9325928ee6e6f8794d0e4366228b03343565c31f7de89ea27"
    "30f5611484119414d873db391292ed4f7bd94e1d8e17debcc7d9f16864a76e94"
    "947ae053ee56e63cc8c93882f9475f5f3a9bf55ba91f81cad9a11fbb3d9808e4"
    "0fd22063edc29fcab3f256d8aca0b0b9b03031a8b4516e8435dd37d5871448af"
    "e9f6082b05542e4eebfafa33d7254b599255abb50d532280b9ab4ce57f2d34f3"
    "693501d628297551c62c58f97dd949bfcd454f8f19c5126abbe83f4ecc2bdecb"
    "dc842b7e2819e230ba89142e007503b8a3bc941d0a5061cbe9f6760e32cd8021"
    "09c7e552bc76492f852f54934da55cc98107fccf064fcf56098954d51fff6580"
    "23b70edb1955c4bfc330de426430f69d4715ed43e8a45c0aa8d7e4dab780a08d"
    "0572b974f03ce0bbb57d2e985e1419c7e8d9ecbe2cf3d73f2fe4b17170e59750"
    "11317ba87905e7907fbf21ec8a1f45ec1725cabfcb045b00964e915cd5e2b207"
    "3e2b8bcbf016d66dbe7444e39328a0acf85b2b4fbcde44b749353fea39ba63b1"
    "1dd01aafcd53486a1fca8a92fd719f85fc7c95d827357afa18a6a990c8b35ebd"
    "cccb7005c6b9c28d3bdbb92c43b17f26aa70b5b4f89695a2e94c39a54a98307f"
    "b7a0b174cff6f36ed4dba84729af48ad2e18bc1ad9704a682de0966daf2f8b1c"
    "b9c11d5b1e43a07e64972d68dee3336094628d38d0c20584dbc0d2b6ab90a559"
    "d2733c4335c6a72f7e75d99d94a70f4d6ced1983376fa72b97fcaacbf030bc24"
    "7b77497b32503b128547eddfb81ccb9479999cdff70902cbcffe1939438e9b24"
    "829626e3892d95d792fae24291f2b3f163e22c147b9c3403c678b6d860284a1c"
    "5873888850659ae70981dcd296a8736d9f65789a6509a4409ff38fed72e9052f"
    "e479ee5b9930578ce7f28ecd2d49eecd56c074a581ea17fe5544f7d774b14aef"
    "7b3f0195fc6f290f12153635b2c0cf577f5126dbba5e0ca77a76956c3eafb413"
    "3d5774a11d31ab398a1b083821f40cb47b4a38e32537df62950113646d1d6e03"
    "4da8979a0041e8a93bc36e078f7515d75d0a12f27ad310d17f9d1a2e1ebe1327"
    "da3a361b1c5157b1dcdd7d20903d0c2536833336d068f707ce68341f79893389"
    "ab9090168dd05f3443954b3252dc25e5b438c2b67f98e5e910dcd78e3851a492"
    "dbc27ab5447822bf9b3cdb65f82ca382b67b7896167b4c84bfced1b0048eac50"
    "a9119b60369ffebd1fff7ac80904bf45ac12fb171817eee7af08da9177dda93d"
    "1b0cab936e65c744b559eb1d04e5e932c37b45b3f8d6f2bac3a9dc228caac9e9"
    "f3b8b6675a6507ff9fc477de4ed681da67378d8eccef96cb6dd856d94d259236"
    "a319ce15b0b4db31073973751f12dd5e8a8e849eb32781a5e1925c71285279f5"
    "74c04bf1790c0efe4dda48153c94938a9d266d6a1cc0542c7440fb816508c4fe"
    "13328503df48229fd6bf7baee43cac404838d65f6ef6748f1e152328f3318dea"
    "8f8419a348f296bf72c8834a5957b511d7a023a73260b45c94ebc8abcfb56dae"
    "9fc10d0f989993e0de68a2355b93cae6a44cfe79ae538bbe9d1d84fcce371425"
    "51d2b1ab2ddfb6362fd7e4b9e72cd38c65ca5b96b7552210dd69a0d8ab3b546d"
    "604d51b25fbf70e273aa8a564fb7ac9e1a8c1e992b941148aac40a2703d9bea0"
    "764dbeae7fa4f3a61e99b96e70a9be8b2c5e9deb57ef47433a938fee32d29981"
    "26e6db8ffdf5adfe469356c504ec9f9dc8763c5b08d1908c3f6c6af859d80055"
    "7f7cc39420a3a5459bfb227ebdf4c5ce89039d79d6fc5c5c8fe88b57305e2ab6"
    "a09e8c8c35ab96defa7e393983325753d6b6d0ecc617c699dfea21ea9e7557e3"
    "b67c1fa481680af8ca1e3785a9e724e51cfc8bed0d681639d18d8549d140caea"
    "4ed0fe7e9dc91335e4dbf0634473f5d21761f93a44d5aefe53898e4c3910da55"
    "734de8181f6ec39a2680b122baa28d97298af231c85bafab7983eed3740847d5"
    "66c1a2a1a60cd8899e17e49642a3e4c1edb454e7badc080550b704cab602c329"
    "4cc317fb9cddd02366b4835d9eafea22219b97e26ffc81bd261e4e4c0a333a9d"
    "1fe2cca76517db90d7504dfa8816edbbb9571fa04dc089c81ddc0325259b27de"
    "cf3f4688801eb9aaf4f5d05c10cab24338b6525c21a42b0e36f60e2ba4fa6800"
    "eb3593803173e0ce9c4cd6257c5a3603af0c317d32adaa8a258e5a80c7204c4b"
    "8b889d624d44885df4d14597e660f855d4347f66ec8941c3e699ed85b0dfb40d"
    "2472f6207c2d0484c2a1e7b5b459aeb5ab4f6451cc1d45ec63767572ae3d6174"
    "a59e0bd101731a28116d0016cb948f092cf9c8ca052f6e9f0b090a7560a968e3"
    "abeeddb2dde06ff158efc10b06a2068dc6e57a78fbd986e02eab8ca63ce802d7"
    "14a195640116f3367c0828dd624ec390d74bbe77e6116ac7804456af10f5fb53"
    "ebe9ea2adf4321c703219a39ee587a3049787fef17af9924a1e9300cd8520548"
    "5b45e522e4b1b4efb49c3b3995091a36d4490ad526f1443112a8f216af9418c2"
    "001f837cc73505241877b51e57a764d5a2853b80f17f58ee993e1de72d36d310"
    "b3598080ce64a656252f59cf0d9f04bbd23c8e176d1136001bda0492e7e4586e"
    "21e0bd5026c619bf3b097adaf088f94e8d14dedb30be846ef95cffa23af5f6f4"
    "3871700761b3f743ca672b91e9e4fa1664c8e531bff53b55241260ed4ad1e87d"
    "106c09b972d2e8227fba195410e5ca307884d9bc6cb569d80647dfedcd894a29"
    "63573ff03e2247744fc8e9560f91b1231db956e450275779b8d91274b9e9d4fb"
    "a2ebee47e2fbfce1d9f1f30ccd97fb09efed53d75fd64e6b2e6d02c36017f67f"
    "a9aa4d20db084e9bb64be8d8b25396c170cb6af7c2d5bcf098f076a4f7a2322e"
    "bf84470805e69b5f94c3251f06f90cf33e003e616a6591e9b925a6cd0421aff3"
    "61bdd1307c66e300bf8d5108e27e0d48240ab57a8b888b20fc87614baf287e07"
    "ef02cdd06ffdb432a1082c0466df6c0a8215e577001332c8d39bb9c3a48db6cf"
    "2738259634305c1461cf4f94c97df93d1b6baca2ae4e125b758f450c88572e0b"
    "959f587d507a8359b063e962e045f54d60e8ed72c0dff5d17b64978555326f9f"
    "fd080d236da814ba8c90fd9b083f4558106f72fe81e2c5907976033a39f7d952"
    "a4ec0132764ca04b733ea705fae4fa77b4d8f77bc3e561679e21f4f903b33fd9"
    "9d765e419fb69f6dd30c088ba61ea5ef5d94337fbfaf7f5b1a4e4822eb4d7a59"
    "6ffe73e81b637fb3ddf957bc36d8b9ca64d0e29eea8838b308dd9bdfd96b9f63"
    "087e79e5a57d1d13e328e230e3e2b3fb1c2559e30f0946be720bf5f26f4d2eaa"
    "b0774d261cc609db443f64ec5a3711954112cf68649a260ed813f2fab7f5c5ca"
    "660d3257380841ee59ac2c7873f910a3e846963877671a1793b633abfa3469f8"
    "c0c0f5a60ef4cdcfcaf21ecd4377b28c57277707199b8175506c11b9d90e8b1d"
    "d83cc2687a19255f4a29c6465a314cd1ed2df21216235097b5635c95ff7296e2"
    "22af003ab672e81152e762596bf682359aeba33ac6ecc6b0944f6de09134dfb6"
    "6c47bec883a7de396ad047c430a12104a5b1cfdba0ab40677c45d833aff07862"
    "5092ef950a16da0b9338e69c052b8e7b455a4b4cfe30e3f56b02e63195ad0cf8"
    "6b17b224bad6bf27d1e0ccd25bb9c169de0c89a556b9ae7050065e535a213cf6"
    "9c1169fa2777b87478edefd694af1eed6dc93d9526a50e68ee97f453f06791ed"
    "32ab0edb696703d33a6853c7e70757a731865ced6120f37d67fef95d92607890"
    "1f2b1d1f15f6dc9cb69e38a8965c6b65aa9119ff184cccf4f43c732873f24c13"
    "fb4a3d794a9a80d23550c2321fd6109c371f77e76bb8417e6bfa9aae5ec05779"
    "cd04f3ff001a4778e3273522064480ca9f91508bffcfc14a049a7f41061a9e60"
    "fcb6be43a9f2fe9b08de8a1c7797da9b8f9887e6078735a1b5b4071dbfc73a66"
    "230e343dfba08d3343ed7f5a0fae657d3a88a0fbbcb05c6321874b8b4d2dbc4f"
    "1bdea12e35f6a8c953c065c6c8e63528e34a1d250e7a8d6bd6b04d3b7651dd7e"
    "5e90277e7cb39e2d2c046f22062dc67db10bb459132d0a263fa9ddfb67e2f199"
    "0e09b88e1914f7af10e8b35af3eeab379eedeca8e272b933d4c718bc4ae8ae5f"
    "81536d601170fc2091b534f885818a06ec8177f83f900978190e714fada5156e"
    "b592bf39b036496389c350c893ae7dc1ac042e70f8b383f2b49b52e587a1ee60"
    "fb152fe3ff26da893e666e6f69ae2c153b544ebe544c19f9e805a1e290cf2456"
    "24b33c9d7ed25117e74733427b72f0c10a804d18b709747557e3306d881edb4f"
    "4ae7d6a36eb5dbcb2d8d5432157064c8d1e649de1e7f268b8a328a1cedfe552c"
    "07a3aec79624c7da84547ddc3e203c94990a98fd5071d2631a4ff12616eefc89"
    "f6f7fd143171420030c05b1ba332f41c8d2636b81555a78646c9feb55d120902"
    "ccec0a73b49c99214e9d2827355fc49219ebb029435dcb0f4659d2b743848a2c"
    "963ef2c96b33be3174f85198b05a2e7d5a0f544dd2b1fb1803727073c2e134b1"
    "c7f6aa2de59aea61352787baa0d7c22f9853eab63b5e0b35abbdcdd7ed5c0860"
    "cf05daf5ac8d77b049cad48cebf4a71e7a4c10ec2158c4a6d9e92aa246bf719e"
    "13ae978d09fe5557730499af921549ff4e4b705b92903ba4ff577222c14f0a3a"
    "55b6344cf97aafaeb862225b055b6960cac09afbddd2cdb4daf8e9829fe96b5f"
    "b5fdfc5d3132c498310cb380db6f7503e87fbb46217a360e2102ae466ebb1148"
    "f8549e1a3aa5e00d07a69afdcc42261ac4c118bfe78feaaef9f4892ed96bd438"
    "1af3dbe25d8f45daf5b4b0b0d2deeeb4962aceefa82e1c84046e3ecaaf453ce9"
    "f05d129681949a4c964781ce734b3c849c2ed44081ce5fbd522e23f3925e319e"
    "177e00f9fc32f7912bc60a63a6f3b3f2222bbfae61725606486289ddcc3d6780"
    "7dc7785b8efdfc808af38731c02ba9801fab64ea29a2ddf7e4d9429322cd065a"
    "9da058c67844f20c24c0e332b70019b0233003b5a6cfe6add586bd01c5c217f6"
    "5e5637885f29bc2b7eba726d8c94094b0a56a5f0bfe39272d79476a84ee20d06"
    "9e4c1269baa4bf3717efee45b0dee6401d95b0a5fcf90bc693cbe0b699c2585d"
    "65fa4f227a2b6d79d5f9e858292504d5c2b5a03f71471a6f59300222b4561e00"
    "ce2f8642ca0712dc7ca9723fbb2e89882785338347f2ba08c61bb3a141e50e8c"
    "150f361dab9dec269f6a419d382595f464a53dc924fe7ac9142de49fff7a7c3d"
    "0c335248857fa9e70a9c32d5eae45305e6c42178c4bbb92e71f1ce2490d20b07"
    "f1bcc3d275afe51ae728e8c83c33407496fbf83a1288462481a1549fd6573da5"
    "5fa7867caf35e14956986e2ef3ed091b917f1dd5f8886c61d20d8c88c8ffe65f"
    "31d71dce64b2c310f165b587df898190a57e6339dd2cf3a01ef6e6dbb1961ec9"
    "70cc73d90bc26e24e21a6b35df0c3ad7003a93d8b28069621c99ded33cb890a1"
    "cf3145de0add4289d0e4427a5514fb7277c621cc9fb3a48367a34dac4356550b"
    "f8d626aaaf278509"
    ))

; The numbers as limbs, made at first use: slot 4k + j + 1 holds limb j,
; the most significant first, of number k.
(def %limbs ())

(def %hex-digit (fn (_ b) (match ((int< b 58) (int- b 48)) (#t (int- b 87)))))

(def %hex-limb
  (fn (_ s i)
    (int| (int<< (%hex-digit (str-byte-ref s i)) 12)
      (int| (int<< (%hex-digit (str-byte-ref s (int+ i 1))) 8)
        (int| (int<< (%hex-digit (str-byte-ref s (int+ i 2))) 4) (%hex-digit (str-byte-ref s (int+ i 3))))))))

(def %limbs!
  (fn (_)
    (when (null? %limbs)
      (def v (Vector make 3124 0))
      (def line
        (fn (self ls slot)
          (unless (null? ls)
            (def s (first ls))
            (def n (int/ (str-byte-len s) 4))
            (List for-each (fn (_ i) (obj-set! v (int+ slot (int+ i 1)) (%hex-limb s (int* i 4)))) (List range 0 n))
            (self (rest ls) (int+ slot n)))))
      (line %hex 0)
      (set! %limbs v))
    %limbs))

; --- the key --------------------------------------------------------------------

(def %key-xor!
  (fn (_ h k)
    (def at (int* k 4))
    (obj-set! h 1 (%xor (obj-ref h 1) (obj-ref %limbs (int+ at 1))))
    (obj-set! h 2 (%xor (obj-ref h 2) (obj-ref %limbs (int+ at 2))))
    (obj-set! h 3 (%xor (obj-ref h 3) (obj-ref %limbs (int+ at 3))))
    (obj-set! h 4 (%xor (obj-ref h 4) (obj-ref %limbs (int+ at 4))))))

; The 0x88 squares of the board, a1 to h8.
(def %squares (List filter (fn (_ sq) (int= (int& sq 136) 0)) (List range 0 128)))

; Whether a pawn PC stands on SQ, which may be off the board.
(def %pawn-on? (fn (_ p sq pc) (match ((int= (int& sq 136) 0) (int= (pos-piece p sq) pc)) (#t #f))))

; P's Polyglot key: a list of four 16-bit limbs, the most significant
; first.
(def polyglot-key
  (fn (_ p)
    (%limbs!)
    (def h (Vector make 4 0))
    (List for-each
      (fn (_ sq)
        (def pc (pos-piece p sq))
        (unless (int= pc 0)
          (%key-xor! h
            (int+ (int* 64 (int+ (int* (int- (int& pc 7) 1) 2) (match ((int< pc 8) 1) (#t 0))))
                  (int+ (int* (int>> sq 4) 8) (int& sq 7))))))
      %squares)
    (def c (pos-castle p))
    (List for-each (fn (_ i) (unless (int= (int& c (int<< 1 i)) 0) (%key-xor! h (int+ 768 i)))) (list 0 1 2 3))
    (def ep (pos-ep p))
    (when (if (int< ep 0) #f
            (if (int= (pos-side p) 0)
              (if (%pawn-on? p (int- ep 15) 1) #t (%pawn-on? p (int- ep 17) 1))
              (if (%pawn-on? p (int+ ep 15) 9) #t (%pawn-on? p (int+ ep 17) 9))))
      (%key-xor! h (int+ 772 (int& ep 7))))
    (when (int= (pos-side p) 0) (%key-xor! h 780))
    (list (obj-ref h 1) (obj-ref h 2) (obj-ref h 3) (obj-ref h 4))))

; A key as 16 hex digits, as Polyglot's tools print it.
(def polyglot-hex
  (fn (_ key)
    (def digit (fn (_ d) (str-byte-sub "0123456789abcdef" d 1)))
    (Str8 join ""
      (List map (fn (_ limb) (Str8 append (digit (int>> limb 12)) (digit (int& (int>> limb 8) 15))
                                          (digit (int& (int>> limb 4) 15)) (digit (int& limb 15))))
        key))))

; Whether key A sorts before key B, limb by limb.
(def %key<
  (fn (self a b)
    (match ((null? a) #f)
           ((int< (first a) (first b)) #t)
           ((int= (first a) (first b)) (self (rest a) (rest b)))
           (#t #f))))

(def %key= (fn (self a b) (match ((null? a) #t) ((int= (first a) (first b)) (self (rest a) (rest b))) (#t #f))))

; --- a Polyglot file ------------------------------------------------------------

(def %byte (fn (_ buf i) (int& (str-byte-ref buf i) 255)))
(def %u16 (fn (_ buf i) (int| (int<< (%byte buf i) 8) (%byte buf (int+ i 1)))))

; Entry I of the book open on FD: (key move weight), read into BUF.
(def %entry
  (fn (_ fd buf i)
    (File seek fd (int* i 16))
    (unless (int= (File read fd buf 16) 16) (Err raise (lit chess) "a short read in the book" i))
    (list (list (%u16 buf 0) (%u16 buf 2) (%u16 buf 4) (%u16 buf 6)) (%u16 buf 8) (%u16 buf 10))))

; The first entry at or past LO, below HI, whose key does not sort
; before KEY.
(def %lower
  (fn (self fd buf key lo hi)
    (if (int< lo hi)
      ((fn (_ mid)
         (if (%key< (first (%entry fd buf mid)) key) (self fd buf key (int+ mid 1) hi) (self fd buf key lo mid)))
       (int/ (int+ lo hi) 2))
      lo)))

; The entries from I on whose key is KEY, as (move . weight).
(def %run
  (fn (self fd buf key i n)
    (if (int< i n)
      ((fn (_ e) (if (%key= (first e) key) (pair (pair (List ref 1 e) (List ref 2 e)) (self fd buf key (int+ i 1) n)) ()))
       (%entry fd buf i))
      ())))

; A Polyglot move in P as the engine's: to and from squares 0 to 63,
; the promotion 1 knight to 4 queen, and castling as the king taking
; its own rook.
(def %polyglot-move
  (fn (_ p pm)
    (def sq (fn (_ s) (int+ (int* (int>> s 3) 16) (int& s 7))))
    (def from (sq (int& (int>> pm 6) 63)))
    (def to0 (sq (int& pm 63)))
    (def promo (int& (int>> pm 12) 7))
    (def to
      (if (if (int= (int& (pos-piece p from) 7) 6) (int= (int& (pos-piece p to0) 7) 4) #f)
        (if (int< to0 from) (int+ from -2) (int+ from 2))
        to0))
    (%find-move p from to (match ((int= promo 0) 0) (#t (int+ promo 1))))))

; The legal move of P from FROM to TO promoting to PROMO, or ().
(def %find-move
  (fn (_ p from to promo)
    (List find
      (fn (_ m)
        (if (if (int= (move-from m) from) (if (int= (move-to m) to) (int= (move-promo m) promo) #f) #f)
          (if (make! p m) (do (unmake! p m) #t) #f)
          #f))
      (gen-moves p #f))))

; The moves the Polyglot book at PATH has for P, as (move . weight),
; the moves it names that are not legal here left out.
(def %polyglot-moves
  (fn (_ path p)
    (def fd (File open path (lit rdonly)))
    (when (int< fd 0) (Err raise (lit chess) (Str8 append "cannot open the book " path) path))
    (def buf (str-make 16))
    (def n (int/ (File seek fd 0 (lit end)) 16))
    (def key (polyglot-key p))
    (def found (guard (e (do (File close fd) (error e))) (%run fd buf key (%lower fd buf key 0 n) n)))
    (File close fd)
    (List reject (fn (_ e) (null? (first e)))
      (List map (fn (_ e) (pair (%polyglot-move p (first e)) (rest e))) found))))

; --- the built-in book ---------------------------------------------------------
;
; Main lines of the openings most played, in SAN from the start.  A
; position's moves are weighted by how many lines play them there.

(def %lines
  (list
    "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O"
    "e4 e5 Nf3 Nc6 Bb5 Nf6 O-O Nxe4 d4 Nd6 Bxc6 dxc6 dxe5 Nf5"
    "e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3 d6 O-O O-O"
    "e4 e5 Nf3 Nc6 Bc4 Nf6 d3 Be7 O-O O-O"
    "e4 e5 Nf3 Nc6 d4 exd4 Nxd4 Nf6 Nxc6 bxc6 e5 Qe7"
    "e4 e5 Nf3 Nf6 Nxe5 d6 Nf3 Nxe4 d4 d5 Bd3"
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6"
    "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 Nf6 Nc3 d6 Bg5 e6"
    "e4 c5 Nf3 e6 d4 cxd4 Nxd4 Nc6 Nc3 Qc7 Be3 a6"
    "e4 c5 c3 Nf6 e5 Nd5 d4 cxd4 Nf3 Nc6"
    "e4 e6 d4 d5 Nc3 Bb4 e5 c5 a3 Bxc3+ bxc3 Ne7"
    "e4 e6 d4 d5 e5 c5 c3 Nc6 Nf3 Qb6"
    "e4 c6 d4 d5 Nc3 dxe4 Nxe4 Bf5 Ng3 Bg6 h4 h6 Nf3 Nd7"
    "e4 c6 d4 d5 e5 Bf5 Nf3 e6 Be2 c5"
    "e4 d5 exd5 Qxd5 Nc3 Qa5 d4 Nf6 Nf3 c6"
    "e4 d6 d4 Nf6 Nc3 g6 Nf3 Bg7 Be2 O-O O-O"
    "d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7 e3 O-O Nf3 h6 Bh4 b6"
    "d4 d5 c4 dxc4 Nf3 Nf6 e3 e6 Bxc4 c5 O-O a6"
    "d4 d5 c4 c6 Nf3 Nf6 Nc3 dxc4 a4 Bf5 e3 e6 Bxc4 Bb4"
    "d4 Nf6 c4 e6 Nc3 Bb4 e3 O-O Bd3 d5 Nf3 c5 O-O"
    "d4 Nf6 c4 e6 Nf3 b6 g3 Ba6 b3 Bb4+ Bd2 Be7"
    "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7"
    "d4 Nf6 c4 g6 Nc3 d5 cxd5 Nxd5 e4 Nxc3 bxc3 Bg7 Nf3 c5"
    "d4 Nf6 c4 c5 d5 e6 Nc3 exd5 cxd5 d6 e4 g6 Nf3 Bg7"
    "d4 f5 g3 Nf6 Bg2 e6 Nf3 Be7 O-O O-O c4 d6"
    "d4 d5 Bf4 Nf6 e3 c5 c3 Nc6 Nd2 e6 Ngf3 Bd6"
    "c4 e5 Nc3 Nf6 Nf3 Nc6 g3 d5 cxd5 Nxd5 Bg2 Nb6 O-O Be7"
    "c4 c5 Nc3 Nc6 g3 g6 Bg2 Bg7 Nf3 e6 O-O Nge7"
    "Nf3 d5 g3 Nf6 Bg2 g6 O-O Bg7 d3 O-O"))

(def %kind-letters ".PNBRQK")

(def %index
  (fn (_ s b)
    (def n (str-byte-len s))
    (def go (fn (self i) (match ((int= i n) -1) ((int= (str-byte-ref s i) b) i) (#t (self (int+ i 1))))))
    (go 0)))

; Whether the byte B of a SAN's disambiguation agrees with FROM: a file
; letter, a rank digit, or the x of a capture.
(def %hint-ok?
  (fn (_ b from)
    (match ((int= b 120) #t)
           ((int< b 57) (int= (int- b 49) (int>> from 4)))
           (#t (int= (int- b 97) (int& from 7))))))

; The legal move SAN names in P.  Only what the book's own lines need is
; read: a piece letter or none, a disambiguation, the square, a
; promotion, castling.
(def %san-move
  (fn (_ p san)
    (def s (Str8 replace "#" "" (Str8 replace "+" "" san)))
    (def base (match ((int= (pos-side p) 0) 0) (#t 112)))
    (def castle (match ((str=? s "O-O") 6) ((str=? s "O-O-O") 2) (#t 0)))
    (def eq (%index s 61))
    (def body (if (int< eq 0) s (str-byte-sub s 0 eq)))
    (def promo (if (int< eq 0) 0 (%index %kind-letters (str-byte-ref s (int+ eq 1)))))
    (def lead (%index %kind-letters (str-byte-ref body 0)))
    (def kind (if (int< 0 castle) 6 (if (int< 1 lead) lead 1)))
    (def n (str-byte-len body))
    (def to (if (int< 0 castle) (int+ base castle) (sq-parse body (int- n 2))))
    (def hints
      (if (int< 0 castle) ()
        (List map (fn (_ i) (str-byte-ref body i)) (List range (if (int= kind 1) 0 1) (int- n 2)))))
    (def m
      (List find
        (fn (_ m)
          (if (if (int= (move-to m) to)
                (if (int= (int& (pos-piece p (move-from m)) 7) kind)
                  (if (int= (move-promo m) promo) (List all? (fn (_ b) (%hint-ok? b (move-from m))) hints) #f) #f) #f)
            (if (make! p m) (do (unmake! p m) #t) #f)
            #f))
        (gen-moves p #f)))
    (when (null? m) (Err raise (lit chess) (Str8 append "the book's move is not legal: " san) san))
    m))

; Each position of the built-in lines with the move played there, as
; (key . move), made at first use, the heap collected at each move: x
; collects only when asked.
(def %builtin ())

(def %builtin!
  (fn (_)
    (when (null? %builtin)
      (def walk
        (fn (self p sans acc)
          (if (null? sans) acc
            ((fn (_ m) (def key (pos-key p)) (make! p m) (Heap collect) (self p (rest sans) (pair (pair key m) acc)))
             (%san-move p (first sans))))))
      (set! %builtin
        (List fold (fn (_ acc line)
                     (walk (pos-from-fen fen-start) (List reject (fn (_ w) (str=? w "")) (Str8 split " " line)) acc))
          () %lines)))
    %builtin))

; MOVES with each move once, weighted by how often it came.
(def %tally
  (fn (_ moves)
    (List fold
      (fn (_ acc m)
        (if (List any? (fn (_ e) (int= (first e) m)) acc)
          (List map (fn (_ e) (if (int= (first e) m) (pair m (int+ (rest e) 1)) e)) acc)
          (List append acc (list (pair m 1)))))
      () moves)))

(def %builtin-moves
  (fn (_ p)
    (def key (pos-key p))
    (%tally (List map rest (List filter (fn (_ e) (str=? (first e) key)) (%builtin!))))))

; --- choosing -------------------------------------------------------------------

; The moves BOOK has for P, as (move . weight); () when it has none.
(def book-moves
  (fn (_ book p)
    (match ((null? book) ())
           ((eq? book (lit builtin)) (%builtin-moves p))
           (#t (%polyglot-moves book p)))))

; A move of BOOK's for P drawn by weight, or () when it has none.  ROLL,
; when given, answers a number below its argument; else the draw is
; random.
(def book-pick
  (fn (_ book p . roll)
    (def moves (List filter (fn (_ e) (int< 0 (rest e))) (book-moves book p)))
    (def total (List fold (fn (_ a e) (int+ a (rest e))) 0 moves))
    (def walk (fn (self ms r) (if (int< r (rest (first ms))) (first (first ms)) (self (rest ms) (int- r (rest (first ms)))))))
    (if (null? moves) ()
      (walk moves (if (null? roll) (chess-roll total) ((first roll) total))))))

; The book the engine plays from: builtin, a Polyglot path, or ().
(def %book (lit builtin))
(def book-current (fn (_) %book))
(def book-use! (fn (_ book) (set! %book book) book))

(provide chess/book polyglot-key polyglot-hex book-moves book-pick book-current book-use!)
