#!/bin/bash

# This script sets up an openaps environment to work with loop.sh,
# by defining the required devices, reports, and aliases.
#
# Released under MIT license. See the accompanying LICENSE.txt file for
# full terms and conditions
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

die() {
  echo "$@"
  exit 1
}

if [[ $# -lt 1 ]]; then
    openaps device show pump 2>/dev/null >/dev/null || die "Usage: setup.sh <pump serial #> [max_iob]"
fi
serial=$1

( ( cd ~/openaps-dev 2>/dev/null && git status ) || ( cd && openaps init openaps-dev ) ) || die "Can't init openaps-dev"
cd ~/openaps-dev || die "Can't cd openaps-dev"

if [[ $# -lt 2 ]]; then
    max_iob=0;
else
    max_iob=$2
fi
( ! grep -q max_iob max_iob.json 2>/dev/null || [[ $max_iob != "0" ]] ) && echo "{ \"max_iob\": $max_iob }" > max_iob.json
cat max_iob.json
git add max_iob.json

# don't re-create devices if they already exist
openaps device show 2>/dev/null > /tmp/openaps-devices

# add devices
grep -q pump.ini .gitignore 2>/dev/null || echo pump.ini >> .gitignore
git add .gitignore
grep pump /tmp/openaps-devices || openaps device add pump medtronic $serial || die "Can't add pump"
grep cgm /tmp/openaps-devices || openaps device add cgm dexcom || die "Can't add CGM"
git add cgm.ini
grep oref0 /tmp/openaps-devices || openaps device add oref0 process oref0 || die "Can't add oref0"
git add oref0.ini
grep iob /tmp/openaps-devices || openaps device add iob process --require "pumphistory profile clock" oref0 calculate-iob || die "Can't add iob"
git add iob.ini
grep get-profile /tmp/openaps-devices || openaps device add get-profile process --require "settings bg_targets isf basal_profile max_iob" oref0 get-profile || die "Can't add get-profile"
git add get-profile.ini
grep determine-basal /tmp/openaps-devices || openaps device add determine-basal process --require "iob temp_basal glucose profile" oref0 determine-basal || die "Can't add determine-basal"
git add determine-basal.ini

# don't re-create reports if they already exist
openaps report show 2>/dev/null > /tmp/openaps-reports

# add reports for frequently-refreshed monitoring data
ls monitor 2>/dev/null >/dev/null || mkdir monitor || die "Can't mkdir monitor"
grep monitor/glucose.json /tmp/openaps-reports || openaps report add monitor/glucose.json JSON cgm iter_glucose 5 || die "Can't add glucose.json"
grep model.json /tmp/openaps-reports || openaps report add model.json JSON pump model || die "Can't add model"
grep monitor/clock.json /tmp/openaps-reports || openaps report add monitor/clock.json JSON pump read_clock || die "Can't add clock.json"
grep monitor/temp_basal.json /tmp/openaps-reports || openaps report add monitor/temp_basal.json JSON pump read_temp_basal || die "Can't add temp_basal.json"
grep monitor/reservoir.json /tmp/openaps-reports || openaps report add monitor/reservoir.json JSON pump reservoir || die "Can't add reservoir.json"
grep monitor/pumphistory.json /tmp/openaps-reports || openaps report add monitor/pumphistory.json JSON pump iter_pump_hours 4 || die "Can't add pumphistory.json"
grep monitor/iob.json /tmp/openaps-reports || openaps report add monitor/iob.json text iob shell monitor/pumphistory.json settings/profile.json monitor/clock.json || die "Can't add iob.json"

# add reports for infrequently-refreshed settings data
ls settings 2>/dev/null >/dev/null || mkdir settings || die "Can't mkdir settings"
grep settings/bg_targets.json /tmp/openaps-reports || openaps report add settings/bg_targets.json JSON pump read_bg_targets || die "Can't add bg_targets.json"
grep settings/insulin_sensitivies.json /tmp/openaps-reports || openaps report add settings/insulin_sensitivies.json JSON pump read_insulin_sensitivies || die "Can't add insulin_sensitivies.json"
grep settings/basal_profile.json /tmp/openaps-reports || openaps report add settings/basal_profile.json JSON pump read_selected_basal_profile || die "Can't add basal_profile.json"
grep settings/settings.json /tmp/openaps-reports || openaps report add settings/settings.json JSON pump read_settings || die "Can't add settings.json"
grep settings/profile.json /tmp/openaps-reports || openaps report add settings/profile.json text get-profile shell settings/settings.json settings/bg_targets.json settings/insulin_sensitivies.json settings/basal_profile.json max_iob.json || die "Can't add profile.json"

# add suggest and enact reports
ls enact 2>/dev/null >/dev/null || mkdir enact || die "Can't mkdir enact"
grep enact/suggested.json /tmp/openaps-reports || openaps report add enact/suggested.json text determine-basal shell monitor/iob.json monitor/temp_basal.json monitor/glucose.json settings/profile.json || die "Can't add suggested.json"
grep enact/enacted.json /tmp/openaps-reports || openaps report add enact/enacted.json JSON pump set_temp_basal enact/suggested.json || die "Can't add enacted.json"

# don't re-create aliases if they already exist
openaps alias show 2>/dev/null > /tmp/openaps-aliases
# add aliases
grep ^invoke /tmp/openaps-aliases || openaps alias add invoke "report invoke" || die "Can't add invoke"
grep ^preflight /tmp/openaps-aliases || openaps alias add preflight '! bash -c "rm  -f model.json &&  openaps report invoke model.json && test -n $(json -f model.json) && echo \"PREFLIGHT OK\" || ( mm-stick warmup fail \"NO PUMP MODEL RESPONDED\" || mm-stick fail \"NO MEDTRONIC CARELINK STICK AVAILABLE\")"' || die "Can't add preflight"
grep ^monitor-cgm /tmp/openaps-aliases || openaps alias add monitor-cgm "report invoke monitor/glucose.json" || die "Can't add monitor-cgm"
grep ^monitor-pump /tmp/openaps-aliases || openaps alias add monitor-pump "report invoke monitor/clock.json monitor/temp_basal.json monitor/pumphistory.json monitor/iob.json" || die "Can't add monitor-pump"
grep ^get-settings /tmp/openaps-aliases || openaps alias add get-settings "report invoke settings/bg_targets.json settings/insulin_sensitivies.json settings/basal_profile.json settings/settings.json settings/profile.json" || die "Can't add get-settings"
grep ^gather /tmp/openaps-aliases || openaps alias add gather '! bash -c "rm monitor/*; openaps monitor-cgm && openaps monitor-pump && openaps get-settings"' || die "Can't add gather"
grep ^enact /tmp/openaps-aliases || openaps alias add enact '! bash -c "rm enact/suggested.json; openaps invoke enact/suggested.json && cat enact/suggested.json && grep -q duration enact/suggested.json && ( openaps invoke enact/enacted.json && cat enact/enacted.json ) || echo No action required"' || die "Can't add enact"
grep ^loop /tmp/openaps-aliases || openaps alias add loop '! bash -c "openaps preflight && openaps gather && openaps enact"' || die "Can't add lop"
grep ^retry-loop /tmp/openaps-aliases || openaps alias add retry-loop '! bash -c "until( ! mm-stick warmup || openaps loop); do sleep 5; done"' || die "Can't add retry-loop"
