/**
 * Called when a client finishes a map in practice mode
 *
 * @param client           	    Index of the client who selected the demo
 * @param demoRunTime		    Time format string of the selected run
 * @param demoStart             Start tick of the selected demo
 * @param demoEnd			    End tick of the selected demo
 * @param demoName			    Name of the demo selected
 * @param dlUrl				    Url to download the demo
 * @param demoPlayer		    Id of the player on the demo
 * @param demoFdl			    FastDL for the map of the selected demo
 * @return						Plugin_Handled, to stop the player from searching.
 */
forward Action SurfTV_SelectedDemo(int client, const char[] demoRunTime, int demoStart, int demoEnd, const char[] demoName, const char[] dlUrl, const char[] demoPlayer, const char[] demoFdl);