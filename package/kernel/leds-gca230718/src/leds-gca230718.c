// SPDX-License-Identifier: GPL-2.0-only
/*
 * GCA230718 LED support (e.g. for D-Link M30) using I2C
 *
 * Copyright 2022 Roland Reinl <reinlroland+github@gmail.com>
 *
 * This driver can control RGBW LEDs which are connected to a GCA230718.
 */

#include <linux/led-class-multicolor.h>
#include <linux/leds.h>
#include <linux/module.h>
#include <linux/of_device.h>
#include <linux/property.h>
#include <linux/i2c.h>
#include <linux/mutex.h>
#include <linux/version.h>

static int gca230718_probe(struct i2c_client *client, const struct i2c_device_id *id)
{
	return 0;
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5,18,0)
static void gca230718_remove(struct i2c_client *client)
#else
static int gca230718_remove(struct i2c_client *client)
#endif
{
#if LINUX_VERSION_CODE < KERNEL_VERSION(5,18,0)
	return 0;
#endif
}

static const struct i2c_device_id gca230718_i2c_ids[] = {
	{ "gca230718", 0 },
};
MODULE_DEVICE_TABLE(i2c, gca230718_i2c_ids);

static const struct of_device_id gca230718_dt_ids[] = {
	{ .compatible = "unknown,gca230718" },
	{},
};
MODULE_DEVICE_TABLE(of, gca230718_dt_ids);

static struct i2c_driver gca230718_driver = {
	.probe		= gca230718_probe,
	.remove		= gca230718_remove,
	.id_table	= gca230718_i2c_ids,
	.driver = {
		.name		= KBUILD_MODNAME,
		.of_match_table	= gca230718_dt_ids,
	},
};

module_i2c_driver(gca230718_driver);

MODULE_AUTHOR("Roland Reinl <reinlroland+github@gmail.com>");
MODULE_DESCRIPTION("GCA230718 LED support (e.g. for D-Link M30) using I2C");
MODULE_LICENSE("GPL");
