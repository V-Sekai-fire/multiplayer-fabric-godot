#pragma once

#include "core/os/os.h"

// poll_until: call Step(), sleep SLEEP_USEC, repeat until IsTerminal(GetState()).
//
// Corresponds to:
//   def pollLoop (p : PollStep) : ClientStatus → ℕ → ClientStatus
//     | s, _ => if isTerminal s then s else pollLoop p (p.step s f).1 ...
//
// No time arithmetic: exits only on state transition.
template <typename GetState, typename IsTerminal, typename Step>
void poll_until(GetState get_state, IsTerminal is_terminal, Step step,
		uint32_t sleep_usec = 50 * 1000) {
	while (!is_terminal(get_state())) {
		step();
		OS::get_singleton()->delay_usec(sleep_usec);
	}
}
