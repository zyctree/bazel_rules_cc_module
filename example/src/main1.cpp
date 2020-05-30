module;

#include <iostream>
#include "include.h"

import main_util;

auto main() -> int {
    std::cout << "hello world " << std::endl;
    return 0;
}

export module _;


module :private;

void do_stuff() {
    std::cout << "Howdy!\n";
}
