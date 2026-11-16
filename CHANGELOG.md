# Changelog

## [0.5.0](https://github.com/kurtschwarz/herder/compare/herder-v0.4.0...herder-v0.5.0) (2026-11-16)


### Features

* **herder:** add a client for choosing a folder ([d93544a](https://github.com/kurtschwarz/herder/commit/d93544a7eee061ea5d85d3629ee60ecda1757973))
* **herder:** add a file explorer pane ([8dc029c](https://github.com/kurtschwarz/herder/commit/8dc029cd6c75b4c332e488509591b7a093dadfff))
* **herder:** add a placeholder command bar over the panes ([f6713a4](https://github.com/kurtschwarz/herder/commit/f6713a4a5f283dc12ed9138f122aab541368dafd))
* **herder:** add a PTY service for terminal sessions ([7f29d9e](https://github.com/kurtschwarz/herder/commit/7f29d9e2c2cb4e8ed0f3851f713f5a7d0305aa86))
* **herder:** add a settings window ([424d450](https://github.com/kurtschwarz/herder/commit/424d450c73a4746da1b7fe8b727839d197fe5877))
* **herder:** add a Task Manager window under Tools ([#83](https://github.com/kurtschwarz/herder/issues/83)) ([1fc3f4a](https://github.com/kurtschwarz/herder/commit/1fc3f4a98a3127604e6fda14c9b5a8e8ac144f1c)), closes [#42](https://github.com/kurtschwarz/herder/issues/42)
* **herder:** add a terminal emulator over libghostty-vt ([c5008e5](https://github.com/kurtschwarz/herder/commit/c5008e581875c50c2237bb0467ae6ab82c569198))
* **herder:** add an agent panel beside the editor ([af60d7a](https://github.com/kurtschwarz/herder/commit/af60d7af50982ed8923629f06d7aeacff4a1175e))
* **herder:** add documents with dirty and stale state ([4fb02f5](https://github.com/kurtschwarz/herder/commit/4fb02f55539643cc0a1b9a40343d2d61dea8b7fd))
* **herder:** add editor footer with branch and file info ([7e41527](https://github.com/kurtschwarz/herder/commit/7e4152701d38139a8f5c3cb047a663201e9829e4))
* **herder:** add herderd and show its connection in Settings ([#89](https://github.com/kurtschwarz/herder/issues/89)) ([92e9d07](https://github.com/kurtschwarz/herder/commit/92e9d07bbe3a6811d99552aeeec9a688afd15bbb))
* **herder:** add modal surfaces and button styles ([ddfb754](https://github.com/kurtschwarz/herder/commit/ddfb754e4deb649e387d091c83d4b2ca624955bb))
* **herder:** add the terminal panel under the editor ([625bcd4](https://github.com/kurtschwarz/herder/commit/625bcd47231dff640ef999bda3fcd64fd7a21eb8))
* **herder:** add the terminal view ([7812de2](https://github.com/kurtschwarz/herder/commit/7812de20bb95f9e4e3b5f3512d335c01dc0f1237))
* **herder:** add wolf app icon ([f37ef40](https://github.com/kurtschwarz/herder/commit/f37ef4070f0cc751efb5b361fe6780074551471d))
* **herder:** add workspaces from a modal ([a336bce](https://github.com/kurtschwarz/herder/commit/a336bce912f3c156bd09d9304f01d959d440fd17))
* **herder:** always offer Start a session in Working & Waiting ([#57](https://github.com/kurtschwarz/herder/issues/57)) ([6515ea1](https://github.com/kurtschwarz/herder/commit/6515ea100a5046c57c07ad0757307cbf5de3d8ea)), closes [#56](https://github.com/kurtschwarz/herder/issues/56)
* **herder:** animate the chevron turning ([dfe4243](https://github.com/kurtschwarz/herder/commit/dfe4243f3b26d65d8d69292d39f7384b29c70b02))
* **herder:** ask before ending a running command ([923bbdb](https://github.com/kurtschwarz/herder/commit/923bbdbc0c4e6e2b2ab23ff8e88f00b7c7d546ec))
* **herder:** ask before losing unsaved edits ([958df31](https://github.com/kurtschwarz/herder/commit/958df312b6cbc8c8505f3b21ad8dea7926dcc1a4))
* **herder:** ask git once about the whole worktree ([64bf4fe](https://github.com/kurtschwarz/herder/commit/64bf4fe8fb2076d7daa79a549efd4a2eb6728810))
* **herder:** close an open session from a hover X on its row ([#74](https://github.com/kurtschwarz/herder/issues/74)) ([291bcd1](https://github.com/kurtschwarz/herder/commit/291bcd14d6692142c5a5765092f3063eaadff162)), closes [#73](https://github.com/kurtschwarz/herder/issues/73)
* **herder:** colour the names of changed files and the folders above them ([#88](https://github.com/kurtschwarz/herder/issues/88)) ([8c38102](https://github.com/kurtschwarz/herder/commit/8c381023ecd8a13e1c58ae87fa05446e5707b65b)), closes [#87](https://github.com/kurtschwarz/herder/issues/87)
* **herder:** create a worktree from a new-session modal ([1fad2a4](https://github.com/kurtschwarz/herder/commit/1fad2a4f0c346317c6668a16224ab3431f7f8d2d))
* **herder:** create an untitled file with ⌘N or a double-click ([#77](https://github.com/kurtschwarz/herder/issues/77)) ([a4f59ff](https://github.com/kurtschwarz/herder/commit/a4f59ff08885bb42a6942390e95ffeed4c9ea67a)), closes [#72](https://github.com/kurtschwarz/herder/issues/72)
* **herder:** create files and folders in the explorer ([beca5c7](https://github.com/kurtschwarz/herder/commit/beca5c739f7c68c4de0c78e1156b6c64f6c18376))
* **herder:** create worktrees and list branches through git ([f2c81c1](https://github.com/kurtschwarz/herder/commit/f2c81c14160e8671c27988768e596f3a3da2001f))
* **herder:** delete files from the explorer ([0c15cc3](https://github.com/kurtschwarz/herder/commit/0c15cc37b08b378c37ffafec32d2752e310bddc3))
* **herder:** double-click the agent tab bar for a session ([a8953a4](https://github.com/kurtschwarz/herder/commit/a8953a41c9a0350b065550f0f5c732a2d6e2c804))
* **herder:** double-click the tab bar for a new terminal ([d83e952](https://github.com/kurtschwarz/herder/commit/d83e9525047405bf4a9f387738d3f4c7f25770c3))
* **herder:** draw icons with Phosphor ([ebbbdd2](https://github.com/kurtschwarz/herder/commit/ebbbdd28c2bbfc94997834c85f11683470a547da))
* **herder:** drop the app sandbox ([47d359c](https://github.com/kurtschwarz/herder/commit/47d359c29e62dd5f02a499cab5d8b10c349eab82))
* **herder:** edit and save files in the editor ([192a74b](https://github.com/kurtschwarz/herder/commit/192a74b2f926e4ce43d894b626bfe7337a75a807))
* **herder:** end agents a crash left running ([0c61a61](https://github.com/kurtschwarz/herder/commit/0c61a61a4180ef67b261f8f5bffbedd086520dfe))
* **herder:** expand All history to show older sessions ([#82](https://github.com/kurtschwarz/herder/issues/82)) ([228f866](https://github.com/kurtschwarz/herder/commit/228f8661fb74a42d543a4b3f984249cd103fc242)), closes [#78](https://github.com/kurtschwarz/herder/issues/78)
* **herder:** fade git-ignored items in the explorer ([3baa4df](https://github.com/kurtschwarz/herder/commit/3baa4df7a406ee97d424e95e1cdd4ae90d0efe9f))
* **herder:** fade worktrees in and out ([0f400a7](https://github.com/kurtschwarz/herder/commit/0f400a7a64f19aba3d88718413cb3a35f1af351c))
* **herder:** follow program pointer shapes (OSC 22) ([#54](https://github.com/kurtschwarz/herder/issues/54)) ([49b3687](https://github.com/kurtschwarz/herder/commit/49b36874dd0a0d022a944fbb0535636b7243a7d2)), closes [#52](https://github.com/kurtschwarz/herder/issues/52)
* **herder:** give debug builds their own herderd socket ([#93](https://github.com/kurtschwarz/herder/issues/93)) ([d61a185](https://github.com/kurtschwarz/herder/commit/d61a185f2537f53fc5ba018e34b258749b238175))
* **herder:** give each window its own workspaces ([808a777](https://github.com/kurtschwarz/herder/commit/808a777ad32dae9226d27652786492623d9c5f35))
* **herder:** highlight syntax in the editor with tree-sitter ([efcae2a](https://github.com/kurtschwarz/herder/commit/efcae2abe69543b678a07aa5130b025066b70187))
* **herder:** highlight the caret's line ([33cb09c](https://github.com/kurtschwarz/herder/commit/33cb09c38a6abe23584ca9a95de8defbb05d6786))
* **herder:** keep the agent panel always on screen ([3834114](https://github.com/kurtschwarz/herder/commit/38341149b62e735d57f90a970788cb8454bf6bde))
* **herder:** list a repository's worktrees from disk ([ca14b0c](https://github.com/kurtschwarz/herder/commit/ca14b0c59d72b033bc5a5c2b2887370d49f3488a))
* **herder:** list open agent sessions in the sidebar ([6bed95f](https://github.com/kurtschwarz/herder/commit/6bed95f6d02728a3b321242ed66083cadb2186e1))
* **herder:** list workspaces and worktrees in sidebar ([9b4982d](https://github.com/kurtschwarz/herder/commit/9b4982d47964bca9fdeab824e46c387ac8fe1b35))
* **herder:** name opencode tabs from OSC 7501 title ([#51](https://github.com/kurtschwarz/herder/issues/51)) ([9964e17](https://github.com/kurtschwarz/herder/commit/9964e17c742cc93a0d90bb2764b518eba0276e9d)), closes [#31](https://github.com/kurtschwarz/herder/issues/31)
* **herder:** nest worktrees under slashed branch names ([170ef9b](https://github.com/kurtschwarz/herder/commit/170ef9b4f771df82ea7a5bab31e79bef9a27ffd9))
* **herder:** open links in terminal output ([#47](https://github.com/kurtschwarz/herder/issues/47)) ([b9c76eb](https://github.com/kurtschwarz/herder/commit/b9c76eb4e08193c5620b1fed5d32298dd3b8f013)), closes [#46](https://github.com/kurtschwarz/herder/issues/46)
* **herder:** open several files as editor tabs ([2341e13](https://github.com/kurtschwarz/herder/commit/2341e1349e7f8e141e8ac0ff00ca2f465efa501a))
* **herder:** open the clicked file in a read-only editor ([256c8a8](https://github.com/kurtschwarz/herder/commit/256c8a8c1847c9e8e87312a34b89ca2b6e588d6c))
* **herder:** persist the list of open workspaces ([e060307](https://github.com/kurtschwarz/herder/commit/e06030789a33616574f1ed48394e23367b15b5bf))
* **herder:** pick which workspaces to show ([#4](https://github.com/kurtschwarz/herder/issues/4)) ([3b5eba2](https://github.com/kurtschwarz/herder/commit/3b5eba2475f42832ccdbbf399403734e2624e7e7))
* **herder:** pick which workspaces to show ([#4](https://github.com/kurtschwarz/herder/issues/4)) ([3b5eba2](https://github.com/kurtschwarz/herder/commit/3b5eba2475f42832ccdbbf399403734e2624e7e7))
* **herder:** pin a terminal tab ([380ad11](https://github.com/kurtschwarz/herder/commit/380ad11dea3a28cbbd727104994935641cfa5788))
* **herder:** plan, build and + buttons on the sidebar ([#81](https://github.com/kurtschwarz/herder/issues/81)) ([2356825](https://github.com/kurtschwarz/herder/commit/2356825fbc50450f069fc3908151e6d590ff9d84)), closes [#79](https://github.com/kurtschwarz/herder/issues/79)
* **herder:** put new worktrees in the repository root ([af3ebb6](https://github.com/kurtschwarz/herder/commit/af3ebb68c7a0e53088c7cc0480b79d807f35c490))
* **herder:** read agent status from OSC 7501 only ([b4dca70](https://github.com/kurtschwarz/herder/commit/b4dca70a0b8edadc590cb0c7066caa26cc93157f))
* **herder:** recognise a project folder with a bare .git ([feab44d](https://github.com/kurtschwarz/herder/commit/feab44d6f34d872bdcc3d7f3f87cf284e8583f8a))
* **herder:** redesign the new session modal ([#16](https://github.com/kurtschwarz/herder/issues/16)) ([f294f8e](https://github.com/kurtschwarz/herder/commit/f294f8e2d6afccd5253d7d3dc59879faecd13e75))
* **herder:** remember last workspace and open file ([1fc6ba5](https://github.com/kurtschwarz/herder/commit/1fc6ba521bf43e2d6119428c278097d13fe1a9c0))
* **herder:** rename a terminal tab ([1171cec](https://github.com/kurtschwarz/herder/commit/1171cecb936be3ef47b29931b7186b4eec2180f6))
* **herder:** rename an agent tab from its menu ([f558c73](https://github.com/kurtschwarz/herder/commit/f558c732bfff7b509e7be7860fcc127c67f878f3))
* **herder:** rename files in the explorer ([5c556ef](https://github.com/kurtschwarz/herder/commit/5c556ef6504dad7d8fc1437504b182b2547a4c26))
* **herder:** reorder editor tabs by dragging ([b2f5bef](https://github.com/kurtschwarz/herder/commit/b2f5befb5eb18d6985a95f91ee4c0b653f2b1064))
* **herder:** replace agent tab bar with session header ([#55](https://github.com/kurtschwarz/herder/issues/55)) ([26f59fc](https://github.com/kurtschwarz/herder/commit/26f59fc0d0c219488c1fac56d36433d9f60d826e)), closes [#53](https://github.com/kurtschwarz/herder/issues/53)
* **herder:** resize the outer panes by dragging ([090e82b](https://github.com/kurtschwarz/herder/commit/090e82b42aae16aeccb50e0f5c68d218413bbda2))
* **herder:** resume agent sessions when a window reopens ([b066387](https://github.com/kurtschwarz/herder/commit/b066387f8fe31894b5c4b872f4231709e828eb8e))
* **herder:** resume opencode sessions by their id ([6ede036](https://github.com/kurtschwarz/herder/commit/6ede036afa1089a42e814f440c92bc1aca07b87f))
* **herder:** session history in the sidebar ([#6](https://github.com/kurtschwarz/herder/issues/6)) ([3e77a37](https://github.com/kurtschwarz/herder/commit/3e77a3719b073f5d49de2d3b4b6f37e88fc38ea4))
* **herder:** set up opencode from the app bundle ([ea8f2dc](https://github.com/kurtschwarz/herder/commit/ea8f2dc76595740d84270c1ccd31650e0669802e))
* **herder:** show a banner when reading an ended session ([#76](https://github.com/kurtschwarz/herder/issues/76)) ([b9593cf](https://github.com/kurtschwarz/herder/commit/b9593cfc70ba4125e1b0264a89e4bbbe99204412))
* **herder:** show a pointing hand over icon buttons ([e6a9581](https://github.com/kurtschwarz/herder/commit/e6a9581db8b7182a3d8ba7b88f4b97aacca43ac2))
* **herder:** show the version and commit in settings ([1cfc728](https://github.com/kurtschwarz/herder/commit/1cfc728a2f42fd286ce375d71882eae33aa35c14))
* **herder:** start any agent's TUI in the panel ([b665394](https://github.com/kurtschwarz/herder/commit/b665394554d18583053b2a3aece9bbfb9ad553de))
* **herder:** style app shell after Tokyo Night mockup ([984e60e](https://github.com/kurtschwarz/herder/commit/984e60eda25809138893daa05867690ab4b28c39))
* **herder:** support the .bare worktree layout ([59a331e](https://github.com/kurtschwarz/herder/commit/59a331ec2cbd89cfd739cba49aeeda7de403c3b5))
* **herder:** theme opencode to match the panel ([fdd8f8b](https://github.com/kurtschwarz/herder/commit/fdd8f8b0f8a6d3de72fd933fc2ad20bbff09b8b1))
* **herder:** update itself from GitHub releases ([1edf5e7](https://github.com/kurtschwarz/herder/commit/1edf5e7ad6e1dc0e28ea9edfc7b281b44c190808))
* **herder:** use liquid glass for window and sidebar ([f961501](https://github.com/kurtschwarz/herder/commit/f961501837069550b98b37203ba53decfd9d8537))
* **herder:** validate and rename workspaces in the store ([0cf1b2f](https://github.com/kurtschwarz/herder/commit/0cf1b2f2abd2f4556687a3bdc96c2017b75ac229))
* **herder:** watch the active worktree in the background ([9151926](https://github.com/kurtschwarz/herder/commit/9151926dae6218cab558315d08a3395bfac3b3d6))
* **herder:** whiten numbers of selected lines ([432ab27](https://github.com/kurtschwarz/herder/commit/432ab27bfe8d28ffdf19cf031211f610b40f6ba2))
* **herder:** zoom window on header double-click ([af3fe95](https://github.com/kurtschwarz/herder/commit/af3fe95a9c54ac066e9fd46c083421ec832b862f))
* **opencode-plugin-osc-7501:** report status ([e1e773a](https://github.com/kurtschwarz/herder/commit/e1e773a91c5d05e38469188367367b2872528f27))
* **opencode-theme:** keep the herder theme in the repo ([b7e29f2](https://github.com/kurtschwarz/herder/commit/b7e29f2b5bf1798696943f8020a8441cc51b4c0b))
* scaffold monorepo with macos app shell ([ebd16f5](https://github.com/kurtschwarz/herder/commit/ebd16f51d8d5adf212f3ec8ad5e1627398da7637))


### Bug Fixes

* **deps:** release on lockfile and toolchain bumps ([#44](https://github.com/kurtschwarz/herder/issues/44)) ([0e54334](https://github.com/kurtschwarz/herder/commit/0e54334a31cd7b3fec323000c21b4c2623777ae0))
* **deps:** update rust crate tree-sitter-css to 0.25 ([#14](https://github.com/kurtschwarz/herder/issues/14)) ([ed3259a](https://github.com/kurtschwarz/herder/commit/ed3259ab9995ba16705434cb2b1238424e404aed))
* **deps:** update rust to v1.100.0 ([#70](https://github.com/kurtschwarz/herder/issues/70)) ([13b39ef](https://github.com/kurtschwarz/herder/commit/13b39ef89414cd37f3d3ab98a0eff439cce0f8f3))
* **herder-ghostty-vt:** build on release tags ([55bb384](https://github.com/kurtschwarz/herder/commit/55bb384fc745f9ac4af02f968823eee4a69830ce))
* **herder:** allow bookmarks to outlive a launch ([ae197cc](https://github.com/kurtschwarz/herder/commit/ae197cceb10f793eabb8aaf89930a5cf405a961f))
* **herder:** bound a terminal's unread output ([6094b8e](https://github.com/kurtschwarz/herder/commit/6094b8eec18eaa7fe6597b8c096c52ceec93c237))
* **herder:** canonicalise the paths the watcher reports ([566727d](https://github.com/kurtschwarz/herder/commit/566727d9362ee5eb888e562aab182be643d01422))
* **herder:** close a session from the sidebar ([#24](https://github.com/kurtschwarz/herder/issues/24)) ([27eebda](https://github.com/kurtschwarz/herder/commit/27eebda23545515c564cefab8004d102f0db03a1))
* **herder:** colour edited text as it is typed ([857f072](https://github.com/kurtschwarz/herder/commit/857f0721cc5bec59328e48f96901b0f6ef64f09d))
* **herder:** draw session history as a timeline ([#37](https://github.com/kurtschwarz/herder/issues/37)) ([67e5e82](https://github.com/kurtschwarz/herder/commit/67e5e829632243d4a73310e75847ff0aef27a2ed)), closes [#34](https://github.com/kurtschwarz/herder/issues/34)
* **herder:** end a tab rename on a click outside it ([c9642a7](https://github.com/kurtschwarz/herder/commit/c9642a73421d3fed200272b7e4eb52ba41528790))
* **herder:** end agents that ignore the hang-up ([9ae2f15](https://github.com/kurtschwarz/herder/commit/9ae2f15e35cfc7303463c140965a8f4df75ebed7))
* **herder:** enlarge the chevron's click target ([c0aee51](https://github.com/kurtschwarz/herder/commit/c0aee51dae0cc1297728d8f02303487bc748c543))
* **herder:** extend the modal scrim under the title bar ([0639126](https://github.com/kurtschwarz/herder/commit/0639126cc17bb1f7c8dde5c3c326e827bb02c6c2))
* **herder:** give PTY processes a controlling tty ([62e1109](https://github.com/kurtschwarz/herder/commit/62e1109fb39e12a235a0663a01b25973068b8afd))
* **herder:** give the add-workspace icon a hover plate ([445e7a1](https://github.com/kurtschwarz/herder/commit/445e7a12d46f616e4a72d22f1d3d68e891675f62))
* **herder:** give the tab bar's empty space something to click ([2493ddd](https://github.com/kurtschwarz/herder/commit/2493ddd0eac0cc931db7bae77d2609cd23aa9acf))
* **herder:** hide only the hovered row's guide line ([b8acc98](https://github.com/kurtschwarz/herder/commit/b8acc98a41d151d23a1fc510919ab999849a0039))
* **herder:** ignore redraws in session activity ([#23](https://github.com/kurtschwarz/herder/issues/23)) ([ad511d3](https://github.com/kurtschwarz/herder/commit/ad511d3885d19431823c831ecb344bd6b08d5bb3))
* **herder:** keep a reopened session's title until the person speaks ([#60](https://github.com/kurtschwarz/herder/issues/60)) ([d79e305](https://github.com/kurtschwarz/herder/commit/d79e305562ab2ac963c2ff25f88f47bf915c2ed9))
* **herder:** keep blocking client work off the calling actor ([28c89af](https://github.com/kurtschwarz/herder/commit/28c89af1fb51b43be052e58867f8beeaf1a8c4ec))
* **herder:** keep closed sessions closed until used ([#43](https://github.com/kurtschwarz/herder/issues/43)) ([b9dc6d5](https://github.com/kurtschwarz/herder/commit/b9dc6d5333dea1317a190e7ba36b26c972b0c4c9)), closes [#33](https://github.com/kurtschwarz/herder/issues/33)
* **herder:** keep the sidebar full height when empty ([d98cabd](https://github.com/kurtschwarz/herder/commit/d98cabd5365622fedf8940fe7bc9e143fec5cd80))
* **herder:** keep traffic lights in place after leaving full screen ([#68](https://github.com/kurtschwarz/herder/issues/68)) ([536a224](https://github.com/kurtschwarz/herder/commit/536a2246c692afa433dc4cd3cee400b32743c950)), closes [#67](https://github.com/kurtschwarz/herder/issues/67)
* **herder:** key session history by repository folder ([#21](https://github.com/kurtschwarz/herder/issues/21)) ([df82bd4](https://github.com/kurtschwarz/herder/commit/df82bd4feb733f8198afbce68c8cd53259c99614))
* **herder:** look up a session after a quick reply ([63f3345](https://github.com/kurtschwarz/herder/commit/63f33452cf0fa2d01fb96aa49ffff80d78fbfa2e))
* **herder:** number the empty line after a final newline ([4a3b211](https://github.com/kurtschwarz/herder/commit/4a3b2111aeaeee5abf9b7569e7fe8a4e86a780af))
* **herder:** open settings on the active space ([#17](https://github.com/kurtschwarz/herder/issues/17)) ([69c8ae0](https://github.com/kurtschwarz/herder/commit/69c8ae0e2c86942dd3a4c9b216f1fc1034f334fe))
* **herder:** paste images and files with Cmd+V ([#38](https://github.com/kurtschwarz/herder/issues/38)) ([0937a96](https://github.com/kurtschwarz/herder/commit/0937a96eb696d48a2dabd0dd75492d4859bb9caf)), closes [#27](https://github.com/kurtschwarz/herder/issues/27)
* **herder:** read pane gap off the main actor ([b3ed742](https://github.com/kurtschwarz/herder/commit/b3ed742aa831604c79ce70555989de94d70cc24b))
* **herder:** read restored open folders on launch ([#41](https://github.com/kurtschwarz/herder/issues/41)) ([d6a897a](https://github.com/kurtschwarz/herder/commit/d6a897aab6d7f08119987267a4768c3be2d6273a)), closes [#40](https://github.com/kurtschwarz/herder/issues/40)
* **herder:** scope open editor files to the worktree showing ([#62](https://github.com/kurtschwarz/herder/issues/62)) ([1bfd633](https://github.com/kurtschwarz/herder/commit/1bfd633f2c380afb9eb46f9925c34cb47f0cbfe5)), closes [#59](https://github.com/kurtschwarz/herder/issues/59)
* **herder:** set env vars on custom agents ([#65](https://github.com/kurtschwarz/herder/issues/65)) ([04792ba](https://github.com/kurtschwarz/herder/commit/04792ba1ef13f5929b5950068bbde5701669c74b))
* **herder:** ship release builds without coverage ([f12377c](https://github.com/kurtschwarz/herder/commit/f12377c1290324c2566361ae78375ba655c82996))
* **herder:** show syntax colour as soon as it lands ([ee1e395](https://github.com/kurtschwarz/herder/commit/ee1e3953e156a96e4a301c5071d4ebb8aec93314))
* **herder:** show the chosen agent tab's terminal ([ebab223](https://github.com/kurtschwarz/herder/commit/ebab223e086df9e1d14a746489d6284d20ed228a))
* **herder:** sort the sidebar's open sessions by recent activity ([#35](https://github.com/kurtschwarz/herder/issues/35)) ([bdec9ac](https://github.com/kurtschwarz/herder/commit/bdec9ac6885457319c9e3717c83b258f7f51b0ad))
* **herder:** stop terminal drags moving the window ([#50](https://github.com/kurtschwarz/herder/issues/50)) ([5fc306b](https://github.com/kurtschwarz/herder/commit/5fc306bd428d4102043dae0948eea9f0a2118e9c)), closes [#49](https://github.com/kurtschwarz/herder/issues/49)
* **herder:** stop text scrolling under the gutter ([24e6542](https://github.com/kurtschwarz/herder/commit/24e6542b3f43f3182c7854f2a519bd8c6fee223c))
* **herder:** stop the branch picker's caret filling the modal ([1b021a9](https://github.com/kurtschwarz/herder/commit/1b021a908781d0ba03d98638c96e601dd35d1562))
* **herder:** stop the chevron waiting on double-click ([3b60340](https://github.com/kurtschwarz/herder/commit/3b603401946528ea80900593e832f237ff4ec80e))
* **herder:** style the base branch picker as a field ([6f20953](https://github.com/kurtschwarz/herder/commit/6f20953f1ffb21c3facfa7481fe5f4d636d6bd57))
* **herder:** trim the agent panel's terminal inset ([26961e8](https://github.com/kurtschwarz/herder/commit/26961e8b5b2881595fbca2831e9facfe0539ab49))
* **herder:** zoom a moved window back into place ([#19](https://github.com/kurtschwarz/herder/issues/19)) ([8d85792](https://github.com/kurtschwarz/herder/commit/8d8579270a4c779fc2ac3dcede656442a50b4eb4))
* **p4a:** keep the persisted entity called Workspace, so the store opens again ([aed63a1](https://github.com/kurtschwarz/herder/commit/aed63a1874b644ecfc380c50a4ae966d6f1dd8e7))
* **terminal:** draw block elements as cell shapes ([d9862d5](https://github.com/kurtschwarz/herder/commit/d9862d549559730b1b39e432c683c49585c03fc5))


### Performance Improvements

* **herder:** bundle only the icons the app uses ([84738af](https://github.com/kurtschwarz/herder/commit/84738af5ff44a71f758588650fce0956cf65447e))
* **herder:** parse the wolf path once ([aee38f0](https://github.com/kurtschwarz/herder/commit/aee38f03cb57a6e1d7912c711864b8ef52d87458))
* **herder:** repaint only the colour that changed ([b72caec](https://github.com/kurtschwarz/herder/commit/b72caec7a92c8fd1ef1c17855ef8b7b724cddabf))
* **herder:** stop git status walking ignored folders ([0aaafec](https://github.com/kurtschwarz/herder/commit/0aaafec3da88e09e7caf4e7a9dd1e21287167286))

## [0.4.0](https://github.com/kurtschwarz/herder/compare/herder-v0.3.3...herder-v0.4.0) (2026-11-16)


### Features

* **herder:** add a Task Manager window under Tools ([#83](https://github.com/kurtschwarz/herder/issues/83)) ([1fc3f4a](https://github.com/kurtschwarz/herder/commit/1fc3f4a98a3127604e6fda14c9b5a8e8ac144f1c)), closes [#42](https://github.com/kurtschwarz/herder/issues/42)
* **herder:** add herderd and show its connection in Settings ([#89](https://github.com/kurtschwarz/herder/issues/89)) ([92e9d07](https://github.com/kurtschwarz/herder/commit/92e9d07bbe3a6811d99552aeeec9a688afd15bbb))
* **herder:** close an open session from a hover X on its row ([#74](https://github.com/kurtschwarz/herder/issues/74)) ([291bcd1](https://github.com/kurtschwarz/herder/commit/291bcd14d6692142c5a5765092f3063eaadff162)), closes [#73](https://github.com/kurtschwarz/herder/issues/73)
* **herder:** colour the names of changed files and the folders above them ([#88](https://github.com/kurtschwarz/herder/issues/88)) ([8c38102](https://github.com/kurtschwarz/herder/commit/8c381023ecd8a13e1c58ae87fa05446e5707b65b)), closes [#87](https://github.com/kurtschwarz/herder/issues/87)
* **herder:** create an untitled file with ⌘N or a double-click ([#77](https://github.com/kurtschwarz/herder/issues/77)) ([a4f59ff](https://github.com/kurtschwarz/herder/commit/a4f59ff08885bb42a6942390e95ffeed4c9ea67a)), closes [#72](https://github.com/kurtschwarz/herder/issues/72)
* **herder:** expand All history to show older sessions ([#82](https://github.com/kurtschwarz/herder/issues/82)) ([228f866](https://github.com/kurtschwarz/herder/commit/228f8661fb74a42d543a4b3f984249cd103fc242)), closes [#78](https://github.com/kurtschwarz/herder/issues/78)
* **herder:** give debug builds their own herderd socket ([#93](https://github.com/kurtschwarz/herder/issues/93)) ([d61a185](https://github.com/kurtschwarz/herder/commit/d61a185f2537f53fc5ba018e34b258749b238175))
* **herder:** plan, build and + buttons on the sidebar ([#81](https://github.com/kurtschwarz/herder/issues/81)) ([2356825](https://github.com/kurtschwarz/herder/commit/2356825fbc50450f069fc3908151e6d590ff9d84)), closes [#79](https://github.com/kurtschwarz/herder/issues/79)
* **herder:** show a banner when reading an ended session ([#76](https://github.com/kurtschwarz/herder/issues/76)) ([b9593cf](https://github.com/kurtschwarz/herder/commit/b9593cfc70ba4125e1b0264a89e4bbbe99204412))

## [0.3.3](https://github.com/kurtschwarz/herder/compare/herder-v0.3.2...herder-v0.3.3) (2026-11-12)


### Bug Fixes

* **deps:** update rust to v1.100.0 ([#70](https://github.com/kurtschwarz/herder/issues/70)) ([13b39ef](https://github.com/kurtschwarz/herder/commit/13b39ef89414cd37f3d3ab98a0eff439cce0f8f3))
* **herder:** keep traffic lights in place after leaving full screen ([#68](https://github.com/kurtschwarz/herder/issues/68)) ([536a224](https://github.com/kurtschwarz/herder/commit/536a2246c692afa433dc4cd3cee400b32743c950)), closes [#67](https://github.com/kurtschwarz/herder/issues/67)

## [0.3.2](https://github.com/kurtschwarz/herder/compare/herder-v0.3.1...herder-v0.3.2) (2026-11-12)


### Bug Fixes

* **herder:** set env vars on custom agents ([#65](https://github.com/kurtschwarz/herder/issues/65)) ([04792ba](https://github.com/kurtschwarz/herder/commit/04792ba1ef13f5929b5950068bbde5701669c74b))

## [0.3.1](https://github.com/kurtschwarz/herder/compare/herder-v0.3.0...herder-v0.3.1) (2026-11-12)


### Bug Fixes

* **herder:** keep a reopened session's title until the person speaks ([#60](https://github.com/kurtschwarz/herder/issues/60)) ([d79e305](https://github.com/kurtschwarz/herder/commit/d79e305562ab2ac963c2ff25f88f47bf915c2ed9))
* **herder:** scope open editor files to the worktree showing ([#62](https://github.com/kurtschwarz/herder/issues/62)) ([1bfd633](https://github.com/kurtschwarz/herder/commit/1bfd633f2c380afb9eb46f9925c34cb47f0cbfe5)), closes [#59](https://github.com/kurtschwarz/herder/issues/59)

## [0.3.0](https://github.com/kurtschwarz/herder/compare/herder-v0.2.7...herder-v0.3.0) (2026-11-12)


### Features

* **herder:** always offer Start a session in Working & Waiting ([#57](https://github.com/kurtschwarz/herder/issues/57)) ([6515ea1](https://github.com/kurtschwarz/herder/commit/6515ea100a5046c57c07ad0757307cbf5de3d8ea)), closes [#56](https://github.com/kurtschwarz/herder/issues/56)
* **herder:** follow program pointer shapes (OSC 22) ([#54](https://github.com/kurtschwarz/herder/issues/54)) ([49b3687](https://github.com/kurtschwarz/herder/commit/49b36874dd0a0d022a944fbb0535636b7243a7d2)), closes [#52](https://github.com/kurtschwarz/herder/issues/52)
* **herder:** name opencode tabs from OSC 7501 title ([#51](https://github.com/kurtschwarz/herder/issues/51)) ([9964e17](https://github.com/kurtschwarz/herder/commit/9964e17c742cc93a0d90bb2764b518eba0276e9d)), closes [#31](https://github.com/kurtschwarz/herder/issues/31)
* **herder:** open links in terminal output ([#47](https://github.com/kurtschwarz/herder/issues/47)) ([b9c76eb](https://github.com/kurtschwarz/herder/commit/b9c76eb4e08193c5620b1fed5d32298dd3b8f013)), closes [#46](https://github.com/kurtschwarz/herder/issues/46)
* **herder:** replace agent tab bar with session header ([#55](https://github.com/kurtschwarz/herder/issues/55)) ([26f59fc](https://github.com/kurtschwarz/herder/commit/26f59fc0d0c219488c1fac56d36433d9f60d826e)), closes [#53](https://github.com/kurtschwarz/herder/issues/53)


### Bug Fixes

* **herder:** stop terminal drags moving the window ([#50](https://github.com/kurtschwarz/herder/issues/50)) ([5fc306b](https://github.com/kurtschwarz/herder/commit/5fc306bd428d4102043dae0948eea9f0a2118e9c)), closes [#49](https://github.com/kurtschwarz/herder/issues/49)

## [0.2.7](https://github.com/kurtschwarz/herder/compare/herder-v0.2.6...herder-v0.2.7) (2026-11-11)


### Bug Fixes

* **deps:** release on lockfile and toolchain bumps ([#44](https://github.com/kurtschwarz/herder/issues/44)) ([0e54334](https://github.com/kurtschwarz/herder/commit/0e54334a31cd7b3fec323000c21b4c2623777ae0))
* **herder:** keep closed sessions closed until used ([#43](https://github.com/kurtschwarz/herder/issues/43)) ([b9dc6d5](https://github.com/kurtschwarz/herder/commit/b9dc6d5333dea1317a190e7ba36b26c972b0c4c9)), closes [#33](https://github.com/kurtschwarz/herder/issues/33)

## [0.2.6](https://github.com/kurtschwarz/herder/compare/herder-v0.2.5...herder-v0.2.6) (2026-11-11)


### Bug Fixes

* **herder:** paste images and files with Cmd+V ([#38](https://github.com/kurtschwarz/herder/issues/38)) ([0937a96](https://github.com/kurtschwarz/herder/commit/0937a96eb696d48a2dabd0dd75492d4859bb9caf)), closes [#27](https://github.com/kurtschwarz/herder/issues/27)
* **herder:** read restored open folders on launch ([#41](https://github.com/kurtschwarz/herder/issues/41)) ([d6a897a](https://github.com/kurtschwarz/herder/commit/d6a897aab6d7f08119987267a4768c3be2d6273a)), closes [#40](https://github.com/kurtschwarz/herder/issues/40)

## [0.2.5](https://github.com/kurtschwarz/herder/compare/herder-v0.2.4...herder-v0.2.5) (2026-11-11)


### Bug Fixes

* **herder:** draw session history as a timeline ([#37](https://github.com/kurtschwarz/herder/issues/37)) ([67e5e82](https://github.com/kurtschwarz/herder/commit/67e5e829632243d4a73310e75847ff0aef27a2ed)), closes [#34](https://github.com/kurtschwarz/herder/issues/34)
* **herder:** sort the sidebar's open sessions by recent activity ([#35](https://github.com/kurtschwarz/herder/issues/35)) ([bdec9ac](https://github.com/kurtschwarz/herder/commit/bdec9ac6885457319c9e3717c83b258f7f51b0ad))

## [0.2.4](https://github.com/kurtschwarz/herder/compare/herder-v0.2.3...herder-v0.2.4) (2026-11-11)


### Bug Fixes

* **herder:** close a session from the sidebar ([#24](https://github.com/kurtschwarz/herder/issues/24)) ([27eebda](https://github.com/kurtschwarz/herder/commit/27eebda23545515c564cefab8004d102f0db03a1))

## [0.2.3](https://github.com/kurtschwarz/herder/compare/herder-v0.2.2...herder-v0.2.3) (2026-11-11)


### Bug Fixes

* **herder:** ignore redraws in session activity ([#23](https://github.com/kurtschwarz/herder/issues/23)) ([ad511d3](https://github.com/kurtschwarz/herder/commit/ad511d3885d19431823c831ecb344bd6b08d5bb3))
* **herder:** key session history by repository folder ([#21](https://github.com/kurtschwarz/herder/issues/21)) ([df82bd4](https://github.com/kurtschwarz/herder/commit/df82bd4feb733f8198afbce68c8cd53259c99614))

## [0.2.2](https://github.com/kurtschwarz/herder/compare/herder-v0.2.1...herder-v0.2.2) (2026-11-10)


### Bug Fixes

* **herder:** zoom a moved window back into place ([#19](https://github.com/kurtschwarz/herder/issues/19)) ([8d85792](https://github.com/kurtschwarz/herder/commit/8d8579270a4c779fc2ac3dcede656442a50b4eb4))

## [0.2.1](https://github.com/kurtschwarz/herder/compare/herder-v0.2.0...herder-v0.2.1) (2026-11-10)


### Bug Fixes

* **herder:** open settings on the active space ([#17](https://github.com/kurtschwarz/herder/issues/17)) ([69c8ae0](https://github.com/kurtschwarz/herder/commit/69c8ae0e2c86942dd3a4c9b216f1fc1034f334fe))

## [0.2.0](https://github.com/kurtschwarz/herder/compare/herder-v0.1.1...herder-v0.2.0) (2026-11-10)


### Features

* **herder:** pick which workspaces to show ([#4](https://github.com/kurtschwarz/herder/issues/4)) ([3b5eba2](https://github.com/kurtschwarz/herder/commit/3b5eba2475f42832ccdbbf399403734e2624e7e7))
* **herder:** pick which workspaces to show ([#4](https://github.com/kurtschwarz/herder/issues/4)) ([3b5eba2](https://github.com/kurtschwarz/herder/commit/3b5eba2475f42832ccdbbf399403734e2624e7e7))
* **herder:** redesign the new session modal ([#16](https://github.com/kurtschwarz/herder/issues/16)) ([f294f8e](https://github.com/kurtschwarz/herder/commit/f294f8e2d6afccd5253d7d3dc59879faecd13e75))
* **herder:** session history in the sidebar ([#6](https://github.com/kurtschwarz/herder/issues/6)) ([3e77a37](https://github.com/kurtschwarz/herder/commit/3e77a3719b073f5d49de2d3b4b6f37e88fc38ea4))


### Bug Fixes

* **deps:** update rust crate tree-sitter-css to 0.25 ([#14](https://github.com/kurtschwarz/herder/issues/14)) ([ed3259a](https://github.com/kurtschwarz/herder/commit/ed3259ab9995ba16705434cb2b1238424e404aed))

## [0.1.1](https://github.com/kurtschwarz/herder/compare/herder-v0.1.0...herder-v0.1.1) (2026-11-09)


### Bug Fixes

* **herder:** ship release builds without coverage ([f12377c](https://github.com/kurtschwarz/herder/commit/f12377c1290324c2566361ae78375ba655c82996))


### Performance Improvements

* **herder:** bundle only the icons the app uses ([84738af](https://github.com/kurtschwarz/herder/commit/84738af5ff44a71f758588650fce0956cf65447e))

## 0.1.0 (2026-11-09)


### Features

* **herder:** add a client for choosing a folder ([d93544a](https://github.com/kurtschwarz/herder/commit/d93544a7eee061ea5d85d3629ee60ecda1757973))
* **herder:** add a file explorer pane ([8dc029c](https://github.com/kurtschwarz/herder/commit/8dc029cd6c75b4c332e488509591b7a093dadfff))
* **herder:** add a placeholder command bar over the panes ([f6713a4](https://github.com/kurtschwarz/herder/commit/f6713a4a5f283dc12ed9138f122aab541368dafd))
* **herder:** add a PTY service for terminal sessions ([7f29d9e](https://github.com/kurtschwarz/herder/commit/7f29d9e2c2cb4e8ed0f3851f713f5a7d0305aa86))
* **herder:** add a settings window ([424d450](https://github.com/kurtschwarz/herder/commit/424d450c73a4746da1b7fe8b727839d197fe5877))
* **herder:** add a terminal emulator over libghostty-vt ([c5008e5](https://github.com/kurtschwarz/herder/commit/c5008e581875c50c2237bb0467ae6ab82c569198))
* **herder:** add an agent panel beside the editor ([af60d7a](https://github.com/kurtschwarz/herder/commit/af60d7af50982ed8923629f06d7aeacff4a1175e))
* **herder:** add documents with dirty and stale state ([4fb02f5](https://github.com/kurtschwarz/herder/commit/4fb02f55539643cc0a1b9a40343d2d61dea8b7fd))
* **herder:** add editor footer with branch and file info ([7e41527](https://github.com/kurtschwarz/herder/commit/7e4152701d38139a8f5c3cb047a663201e9829e4))
* **herder:** add modal surfaces and button styles ([ddfb754](https://github.com/kurtschwarz/herder/commit/ddfb754e4deb649e387d091c83d4b2ca624955bb))
* **herder:** add the terminal panel under the editor ([625bcd4](https://github.com/kurtschwarz/herder/commit/625bcd47231dff640ef999bda3fcd64fd7a21eb8))
* **herder:** add the terminal view ([7812de2](https://github.com/kurtschwarz/herder/commit/7812de20bb95f9e4e3b5f3512d335c01dc0f1237))
* **herder:** add wolf app icon ([f37ef40](https://github.com/kurtschwarz/herder/commit/f37ef4070f0cc751efb5b361fe6780074551471d))
* **herder:** add workspaces from a modal ([a336bce](https://github.com/kurtschwarz/herder/commit/a336bce912f3c156bd09d9304f01d959d440fd17))
* **herder:** animate the chevron turning ([dfe4243](https://github.com/kurtschwarz/herder/commit/dfe4243f3b26d65d8d69292d39f7384b29c70b02))
* **herder:** ask before ending a running command ([923bbdb](https://github.com/kurtschwarz/herder/commit/923bbdbc0c4e6e2b2ab23ff8e88f00b7c7d546ec))
* **herder:** ask before losing unsaved edits ([958df31](https://github.com/kurtschwarz/herder/commit/958df312b6cbc8c8505f3b21ad8dea7926dcc1a4))
* **herder:** ask git once about the whole worktree ([64bf4fe](https://github.com/kurtschwarz/herder/commit/64bf4fe8fb2076d7daa79a549efd4a2eb6728810))
* **herder:** create a worktree from a new-session modal ([1fad2a4](https://github.com/kurtschwarz/herder/commit/1fad2a4f0c346317c6668a16224ab3431f7f8d2d))
* **herder:** create files and folders in the explorer ([beca5c7](https://github.com/kurtschwarz/herder/commit/beca5c739f7c68c4de0c78e1156b6c64f6c18376))
* **herder:** create worktrees and list branches through git ([f2c81c1](https://github.com/kurtschwarz/herder/commit/f2c81c14160e8671c27988768e596f3a3da2001f))
* **herder:** delete files from the explorer ([0c15cc3](https://github.com/kurtschwarz/herder/commit/0c15cc37b08b378c37ffafec32d2752e310bddc3))
* **herder:** double-click the agent tab bar for a session ([a8953a4](https://github.com/kurtschwarz/herder/commit/a8953a41c9a0350b065550f0f5c732a2d6e2c804))
* **herder:** double-click the tab bar for a new terminal ([d83e952](https://github.com/kurtschwarz/herder/commit/d83e9525047405bf4a9f387738d3f4c7f25770c3))
* **herder:** draw icons with Phosphor ([ebbbdd2](https://github.com/kurtschwarz/herder/commit/ebbbdd28c2bbfc94997834c85f11683470a547da))
* **herder:** drop the app sandbox ([47d359c](https://github.com/kurtschwarz/herder/commit/47d359c29e62dd5f02a499cab5d8b10c349eab82))
* **herder:** edit and save files in the editor ([192a74b](https://github.com/kurtschwarz/herder/commit/192a74b2f926e4ce43d894b626bfe7337a75a807))
* **herder:** end agents a crash left running ([0c61a61](https://github.com/kurtschwarz/herder/commit/0c61a61a4180ef67b261f8f5bffbedd086520dfe))
* **herder:** fade git-ignored items in the explorer ([3baa4df](https://github.com/kurtschwarz/herder/commit/3baa4df7a406ee97d424e95e1cdd4ae90d0efe9f))
* **herder:** fade worktrees in and out ([0f400a7](https://github.com/kurtschwarz/herder/commit/0f400a7a64f19aba3d88718413cb3a35f1af351c))
* **herder:** give each window its own workspaces ([808a777](https://github.com/kurtschwarz/herder/commit/808a777ad32dae9226d27652786492623d9c5f35))
* **herder:** highlight syntax in the editor with tree-sitter ([efcae2a](https://github.com/kurtschwarz/herder/commit/efcae2abe69543b678a07aa5130b025066b70187))
* **herder:** highlight the caret's line ([33cb09c](https://github.com/kurtschwarz/herder/commit/33cb09c38a6abe23584ca9a95de8defbb05d6786))
* **herder:** keep the agent panel always on screen ([3834114](https://github.com/kurtschwarz/herder/commit/38341149b62e735d57f90a970788cb8454bf6bde))
* **herder:** list a repository's worktrees from disk ([ca14b0c](https://github.com/kurtschwarz/herder/commit/ca14b0c59d72b033bc5a5c2b2887370d49f3488a))
* **herder:** list open agent sessions in the sidebar ([6bed95f](https://github.com/kurtschwarz/herder/commit/6bed95f6d02728a3b321242ed66083cadb2186e1))
* **herder:** list workspaces and worktrees in sidebar ([9b4982d](https://github.com/kurtschwarz/herder/commit/9b4982d47964bca9fdeab824e46c387ac8fe1b35))
* **herder:** nest worktrees under slashed branch names ([170ef9b](https://github.com/kurtschwarz/herder/commit/170ef9b4f771df82ea7a5bab31e79bef9a27ffd9))
* **herder:** open several files as editor tabs ([2341e13](https://github.com/kurtschwarz/herder/commit/2341e1349e7f8e141e8ac0ff00ca2f465efa501a))
* **herder:** open the clicked file in a read-only editor ([256c8a8](https://github.com/kurtschwarz/herder/commit/256c8a8c1847c9e8e87312a34b89ca2b6e588d6c))
* **herder:** persist the list of open workspaces ([e060307](https://github.com/kurtschwarz/herder/commit/e06030789a33616574f1ed48394e23367b15b5bf))
* **herder:** pin a terminal tab ([380ad11](https://github.com/kurtschwarz/herder/commit/380ad11dea3a28cbbd727104994935641cfa5788))
* **herder:** put new worktrees in the repository root ([af3ebb6](https://github.com/kurtschwarz/herder/commit/af3ebb68c7a0e53088c7cc0480b79d807f35c490))
* **herder:** read agent status from OSC 7501 only ([b4dca70](https://github.com/kurtschwarz/herder/commit/b4dca70a0b8edadc590cb0c7066caa26cc93157f))
* **herder:** recognise a project folder with a bare .git ([feab44d](https://github.com/kurtschwarz/herder/commit/feab44d6f34d872bdcc3d7f3f87cf284e8583f8a))
* **herder:** remember last workspace and open file ([1fc6ba5](https://github.com/kurtschwarz/herder/commit/1fc6ba521bf43e2d6119428c278097d13fe1a9c0))
* **herder:** rename a terminal tab ([1171cec](https://github.com/kurtschwarz/herder/commit/1171cecb936be3ef47b29931b7186b4eec2180f6))
* **herder:** rename an agent tab from its menu ([f558c73](https://github.com/kurtschwarz/herder/commit/f558c732bfff7b509e7be7860fcc127c67f878f3))
* **herder:** rename files in the explorer ([5c556ef](https://github.com/kurtschwarz/herder/commit/5c556ef6504dad7d8fc1437504b182b2547a4c26))
* **herder:** reorder editor tabs by dragging ([b2f5bef](https://github.com/kurtschwarz/herder/commit/b2f5befb5eb18d6985a95f91ee4c0b653f2b1064))
* **herder:** resize the outer panes by dragging ([090e82b](https://github.com/kurtschwarz/herder/commit/090e82b42aae16aeccb50e0f5c68d218413bbda2))
* **herder:** resume agent sessions when a window reopens ([b066387](https://github.com/kurtschwarz/herder/commit/b066387f8fe31894b5c4b872f4231709e828eb8e))
* **herder:** resume opencode sessions by their id ([6ede036](https://github.com/kurtschwarz/herder/commit/6ede036afa1089a42e814f440c92bc1aca07b87f))
* **herder:** set up opencode from the app bundle ([ea8f2dc](https://github.com/kurtschwarz/herder/commit/ea8f2dc76595740d84270c1ccd31650e0669802e))
* **herder:** show a pointing hand over icon buttons ([e6a9581](https://github.com/kurtschwarz/herder/commit/e6a9581db8b7182a3d8ba7b88f4b97aacca43ac2))
* **herder:** show the version and commit in settings ([1cfc728](https://github.com/kurtschwarz/herder/commit/1cfc728a2f42fd286ce375d71882eae33aa35c14))
* **herder:** start any agent's TUI in the panel ([b665394](https://github.com/kurtschwarz/herder/commit/b665394554d18583053b2a3aece9bbfb9ad553de))
* **herder:** style app shell after Tokyo Night mockup ([984e60e](https://github.com/kurtschwarz/herder/commit/984e60eda25809138893daa05867690ab4b28c39))
* **herder:** support the .bare worktree layout ([59a331e](https://github.com/kurtschwarz/herder/commit/59a331ec2cbd89cfd739cba49aeeda7de403c3b5))
* **herder:** theme opencode to match the panel ([fdd8f8b](https://github.com/kurtschwarz/herder/commit/fdd8f8b0f8a6d3de72fd933fc2ad20bbff09b8b1))
* **herder:** update itself from GitHub releases ([1edf5e7](https://github.com/kurtschwarz/herder/commit/1edf5e7ad6e1dc0e28ea9edfc7b281b44c190808))
* **herder:** use liquid glass for window and sidebar ([f961501](https://github.com/kurtschwarz/herder/commit/f961501837069550b98b37203ba53decfd9d8537))
* **herder:** validate and rename workspaces in the store ([0cf1b2f](https://github.com/kurtschwarz/herder/commit/0cf1b2f2abd2f4556687a3bdc96c2017b75ac229))
* **herder:** watch the active worktree in the background ([9151926](https://github.com/kurtschwarz/herder/commit/9151926dae6218cab558315d08a3395bfac3b3d6))
* **herder:** whiten numbers of selected lines ([432ab27](https://github.com/kurtschwarz/herder/commit/432ab27bfe8d28ffdf19cf031211f610b40f6ba2))
* **herder:** zoom window on header double-click ([af3fe95](https://github.com/kurtschwarz/herder/commit/af3fe95a9c54ac066e9fd46c083421ec832b862f))
* **opencode-plugin-osc-7501:** report status ([e1e773a](https://github.com/kurtschwarz/herder/commit/e1e773a91c5d05e38469188367367b2872528f27))
* **opencode-theme:** keep the herder theme in the repo ([b7e29f2](https://github.com/kurtschwarz/herder/commit/b7e29f2b5bf1798696943f8020a8441cc51b4c0b))
* scaffold monorepo with macos app shell ([ebd16f5](https://github.com/kurtschwarz/herder/commit/ebd16f51d8d5adf212f3ec8ad5e1627398da7637))


### Bug Fixes

* **herder:** allow bookmarks to outlive a launch ([ae197cc](https://github.com/kurtschwarz/herder/commit/ae197cceb10f793eabb8aaf89930a5cf405a961f))
* **herder:** bound a terminal's unread output ([6094b8e](https://github.com/kurtschwarz/herder/commit/6094b8eec18eaa7fe6597b8c096c52ceec93c237))
* **herder:** canonicalise the paths the watcher reports ([566727d](https://github.com/kurtschwarz/herder/commit/566727d9362ee5eb888e562aab182be643d01422))
* **herder:** colour edited text as it is typed ([857f072](https://github.com/kurtschwarz/herder/commit/857f0721cc5bec59328e48f96901b0f6ef64f09d))
* **herder:** end a tab rename on a click outside it ([c9642a7](https://github.com/kurtschwarz/herder/commit/c9642a73421d3fed200272b7e4eb52ba41528790))
* **herder:** end agents that ignore the hang-up ([9ae2f15](https://github.com/kurtschwarz/herder/commit/9ae2f15e35cfc7303463c140965a8f4df75ebed7))
* **herder:** enlarge the chevron's click target ([c0aee51](https://github.com/kurtschwarz/herder/commit/c0aee51dae0cc1297728d8f02303487bc748c543))
* **herder:** extend the modal scrim under the title bar ([0639126](https://github.com/kurtschwarz/herder/commit/0639126cc17bb1f7c8dde5c3c326e827bb02c6c2))
* **herder:** give PTY processes a controlling tty ([62e1109](https://github.com/kurtschwarz/herder/commit/62e1109fb39e12a235a0663a01b25973068b8afd))
* **herder:** give the add-workspace icon a hover plate ([445e7a1](https://github.com/kurtschwarz/herder/commit/445e7a12d46f616e4a72d22f1d3d68e891675f62))
* **herder:** give the tab bar's empty space something to click ([2493ddd](https://github.com/kurtschwarz/herder/commit/2493ddd0eac0cc931db7bae77d2609cd23aa9acf))
* **herder:** hide only the hovered row's guide line ([b8acc98](https://github.com/kurtschwarz/herder/commit/b8acc98a41d151d23a1fc510919ab999849a0039))
* **herder:** keep blocking client work off the calling actor ([28c89af](https://github.com/kurtschwarz/herder/commit/28c89af1fb51b43be052e58867f8beeaf1a8c4ec))
* **herder:** keep the sidebar full height when empty ([d98cabd](https://github.com/kurtschwarz/herder/commit/d98cabd5365622fedf8940fe7bc9e143fec5cd80))
* **herder:** look up a session after a quick reply ([63f3345](https://github.com/kurtschwarz/herder/commit/63f33452cf0fa2d01fb96aa49ffff80d78fbfa2e))
* **herder:** number the empty line after a final newline ([4a3b211](https://github.com/kurtschwarz/herder/commit/4a3b2111aeaeee5abf9b7569e7fe8a4e86a780af))
* **herder:** read pane gap off the main actor ([b3ed742](https://github.com/kurtschwarz/herder/commit/b3ed742aa831604c79ce70555989de94d70cc24b))
* **herder:** show syntax colour as soon as it lands ([ee1e395](https://github.com/kurtschwarz/herder/commit/ee1e3953e156a96e4a301c5071d4ebb8aec93314))
* **herder:** show the chosen agent tab's terminal ([ebab223](https://github.com/kurtschwarz/herder/commit/ebab223e086df9e1d14a746489d6284d20ed228a))
* **herder:** stop text scrolling under the gutter ([24e6542](https://github.com/kurtschwarz/herder/commit/24e6542b3f43f3182c7854f2a519bd8c6fee223c))
* **herder:** stop the branch picker's caret filling the modal ([1b021a9](https://github.com/kurtschwarz/herder/commit/1b021a908781d0ba03d98638c96e601dd35d1562))
* **herder:** stop the chevron waiting on double-click ([3b60340](https://github.com/kurtschwarz/herder/commit/3b603401946528ea80900593e832f237ff4ec80e))
* **herder:** style the base branch picker as a field ([6f20953](https://github.com/kurtschwarz/herder/commit/6f20953f1ffb21c3facfa7481fe5f4d636d6bd57))
* **herder:** trim the agent panel's terminal inset ([26961e8](https://github.com/kurtschwarz/herder/commit/26961e8b5b2881595fbca2831e9facfe0539ab49))
* **p4a:** keep the persisted entity called Workspace, so the store opens again ([aed63a1](https://github.com/kurtschwarz/herder/commit/aed63a1874b644ecfc380c50a4ae966d6f1dd8e7))
* **terminal:** draw block elements as cell shapes ([d9862d5](https://github.com/kurtschwarz/herder/commit/d9862d549559730b1b39e432c683c49585c03fc5))


### Performance Improvements

* **herder:** parse the wolf path once ([aee38f0](https://github.com/kurtschwarz/herder/commit/aee38f03cb57a6e1d7912c711864b8ef52d87458))
* **herder:** repaint only the colour that changed ([b72caec](https://github.com/kurtschwarz/herder/commit/b72caec7a92c8fd1ef1c17855ef8b7b724cddabf))
* **herder:** stop git status walking ignored folders ([0aaafec](https://github.com/kurtschwarz/herder/commit/0aaafec3da88e09e7caf4e7a9dd1e21287167286))
