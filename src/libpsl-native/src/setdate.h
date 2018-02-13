// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#pragma once

#include "pal.h"

#include <time.h>

PAL_BEGIN_EXTERNC

int32_t SetDate(struct tm* time);

PAL_END_EXTERNC
