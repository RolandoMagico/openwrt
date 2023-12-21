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

#define GCA230718_MAX_LEDS				(4u)

struct gca230718_led
{
	u8 used;
	enum led_brightness brightness;
	struct i2c_client *client;
	struct led_classdev ledClassDev;
};

struct gca230718_private
{
	struct mutex lock;
	struct gca230718_led leds[GCA230718_MAX_LEDS];
	u8 txData[15];
};

static int gca230718_set_brightness(struct led_classdev *led_cdev, enum led_brightness value)
{
	u8 ledIndex;
	u8 resetCommand[2];
	u8 controlCommand[13];
	struct gca230718_led* led;
	struct i2c_client* client;
	struct gca230718_private* data;

	pr_info("Enter gca230718_set_brightness\n");
	led = container_of(led_cdev, struct gca230718_led, ledClassDev);
	client = led->client;
	data = i2c_get_clientdata(client);

	if (led->used == 1)
	{
		led->brightness = value;
		pr_info("Setting brighness to %u\n", (u32)value);
	}

	resetCommand[0] = 0x81;
	resetCommand[1] = 0xE4;

	controlCommand[0] = 0x0C;
	controlCommand[2] = 0x01;
	controlCommand[7] = 0x01; /* Frequency */
	controlCommand[12] = 0x87;

	for (ledIndex = 0; ledIndex < GCA230718_MAX_LEDS; ledIndex++)
	{
		controlCommand[3 + ledIndex] = data->leds[ledIndex].brightness;
		controlCommand[8 + ledIndex] = data->leds[ledIndex].brightness;
	}

	mutex_lock(&data->lock);
	controlCommand[1] = 0x02;
	i2c_smbus_write_block_data(client, 0x00, sizeof(resetCommand), resetCommand);
	i2c_smbus_write_block_data(client, 0x03, sizeof(controlCommand), controlCommand);

	controlCommand[1] = 0x01;
	i2c_smbus_write_block_data(client, 0x00, sizeof(resetCommand), resetCommand);
	i2c_smbus_write_block_data(client, 0x03, sizeof(controlCommand), controlCommand);

	controlCommand[1] = 0x03;
	i2c_smbus_write_block_data(client, 0x00, sizeof(resetCommand), resetCommand);
	i2c_smbus_write_block_data(client, 0x03, sizeof(controlCommand), controlCommand);
	mutex_unlock(&data->lock);

	pr_info("Exit gca230718_set_brightness\n");

	return 0;
}

static int gca230718_probe(struct i2c_client *client, const struct i2c_device_id *id)
{
	int status;
	struct device_node* gca230718;
	struct device_node* ledNode;
	struct gca230718_private* gca230718_privateData;

	pr_info("Enter gca230718_probe for device address %u\n", client->addr);
	gca230718_privateData = devm_kzalloc(&(client->dev), sizeof(struct gca230718_private), GFP_KERNEL);

	if (gca230718_privateData == NULL)
	{
		pr_info("Error during allocating memory for private data\n");
		status = -ENOMEM;
	}
	else
	{
		mutex_init(&gca230718_privateData->lock);
		i2c_set_clientdata(client, gca230718_privateData);

		gca230718 = client->dev.of_node;

		for_each_child_of_node(gca230718, ledNode)
		{
			u32 regValue = 0;
			if (of_property_read_u32(ledNode, "reg", &regValue) != 0)
			{
				pr_info("Missing entry \"reg\" in node %s\n", ledNode->name); 
			}
			else if (regValue >= GCA230718_MAX_LEDS)
			{
				pr_info("Invalid entry \"reg\" in node %s (%u)\n", ledNode->name, regValue);
			}
			else if (gca230718_privateData->leds[regValue].used == 1)
			{
				pr_info("Duplicate \"reg\" in node %s (%u)\n", ledNode->name, regValue);
			}
			else
			{
				struct led_classdev* ledClassDev = &(gca230718_privateData->leds[regValue].ledClassDev);
				struct led_init_data init_data = {};

				gca230718_privateData->leds[regValue].used = 1;
				gca230718_privateData->leds[regValue].client = client;
				init_data.fwnode = of_fwnode_handle(ledNode);

				pr_info("Creating LED for node %s: reg=%u\n", ledNode->name, regValue); 

				ledClassDev->name = of_get_property(ledNode, "label", NULL);
				if (ledClassDev->name == NULL)
				{
					ledClassDev->name = ledNode->name;
				}

				ledClassDev->brightness = LED_OFF;
				ledClassDev->max_brightness = LED_FULL;
				ledClassDev->brightness_set_blocking = gca230718_set_brightness;
	
				if (devm_led_classdev_register_ext(&(client->dev), ledClassDev, &init_data) != 0)
				{
					pr_info("Error during call of devm_led_classdev_register_ext");
				}
				else
				{

				}
			}
		}
	}

	pr_info("Exit gca230718_probe\n");

	return 0;
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5,18,0)
static void gca230718_remove(struct i2c_client *client)
#else
static int gca230718_remove(struct i2c_client *client)
#endif
{
	struct gca230718_private* gca230718_privateData;
	
	pr_info("Enter gca230718_remove\n"); 

	gca230718_privateData = i2c_get_clientdata(client);
	mutex_destroy(&gca230718_privateData->lock);

	pr_info("Exit gca230718_remove\n"); 

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
