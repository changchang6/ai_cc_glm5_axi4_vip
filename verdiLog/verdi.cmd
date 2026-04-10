verdiDockWidgetDisplay -dock widgetDock_<Signal_List>
simSetSimulator "-vcssv" -exec "./simv_axi4_data_first_test" -args \
           "+UVM_TESTNAME=axi4_data_first_test +UVM_VERBOSITY=UVM_MEDIUM -l sim_axi4_data_first_test.log +ntb_random_seed=1" \
           -uvmDebug on -simDelim
debImport "-i" "-simflow" "-dbdir" "./simv_axi4_data_first_test.daidir"
srcTBInvokeSim
srcTBRunSim
wvCreateWindow
wvRestoreSignal -win $_nWave3 \
           "/home/xingchangchang/ai_evaluation/claude_code/axi4_vip/ai_cc_glm5_axi4_vip/signal.rc" \
           -overWriteAutoAlias on -appendSignals on
wvZoomAll -win $_nWave3
srcSignalView -off
verdiDockWidgetMaximize -dock windowDock_nWave_3
srcSignalView -on
verdiDockWidgetDisplay -dock widgetDock_<Signal_List>
srcSignalView -off
srcSignalView -on
verdiDockWidgetDisplay -dock widgetDock_<Signal_List>
verdiDockWidgetRestore -dock windowDock_nWave_3
verdiDockWidgetSetCurTab -dock windowDock_InteractiveConsole_2
viaLogViewerGrepStart -logID 1 -key { UVM_ERROR} -caseInsensitive -next -window "$_InteractiveConsole_2"
verdiDockWidgetSetCurTab -dock windowDock_nWave_3
wvSelectSignal -win $_nWave3 {( "mst_if/aw" 5 )} 
wvZoom -win $_nWave3 0.000000 660469.804318
wvSetCursor -win $_nWave3 222236.353410 -snap {("aw" 5)}
wvShowFilterTextField -win $_nWave3 -on
wvSelectSignal -win $_nWave3 {( "mst_if/r" 4 )} 
wvZoom -win $_nWave3 0.000000 88255.414319
wvSelectSignal -win $_nWave3 {( "mst_if/r" 3 )} 
wvSetCursor -win $_nWave3 15433.528505 -snap {("r" 3)}
wvZoomAll -win $_nWave3
verdiDockWidgetSetCurTab -dock windowDock_OneSearch
verdiDockWidgetSetCurTab -dock windowDock_InteractiveConsole_2
viaLogViewerGrepStart -logID 1 -key { UVM_ERROR} -caseInsensitive -next -window "$_InteractiveConsole_2"
verdiDockWidgetSetCurTab -dock windowDock_nWave_3
wvSelectSignal -win $_nWave3 {( "mst_if/aw" 5 )} 
wvSetSearchMode -win $_nWave3 -value 
wvSetSearchMode -win $_nWave3 -value 
wvSelectSignal -win $_nWave3 {( "mst_if/aw" 5 )} 
wvZoom -win $_nWave3 475669.562816 967555.133456
wvSetSearchMode -win $_nWave3 -anyChange
wvSetSearchMode -win $_nWave3 -value 
wvSetCursor -win $_nWave3 542899.205927 -snap {("aw" 5)}
wvPanDown -win $_nWave3
wvSearchNext -win $_nWave3
wvScrollUp -win $_nWave3 9
wvSetCursor -win $_nWave3 223193.360631 -snap {("aw" 5)}
debExit
