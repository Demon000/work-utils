### Commit message
 * put a few paragraphs from the datasheet in the commit description of patches
 * signoff
 * make sure to grab tags given upstream during a review if a further version is needed


### Device tree
 * use standard unit prefixes in device tree bindings where applicable, see Documentation/devicetree/bindings/property-units.txt
 * try to use existing $ref when writing device tree bindings, eg $ref: adc.yaml, see below
 * use `additionalProperties: false` for all objects, except when referencing another schema, in which case, use `unevaluatedProperties: false`, see below
 * use hex for matching against unit addresses in patternProperties, eg:
```
patternProperties:
  "^channel@([0-9a-f])$":
    type: object
    $ref: adc.yaml
    unevaluatedProperties: false
```
 * do not use the `-en` suffix for boolean flags
 * don't need the `|` at the start of a `description: |` if there's no formatting to preserve
 * inherit schema for SPI peripherals, eg: (put this after the `required` list
```
allOf:
  - $ref: /schemas/spi/spi-peripheral-props.yaml#

unevaluatedProperties: false
```
 * check your bindings before submitting (also done automatically in our CI now)
```
make dt_binding_check DT_CHECKER_FLAGS=-m DT_SCHEMA_FILES=iio/adc/device.yaml
```
 * Output and input voltage ranges can be expressed like this
```
  adi,conv2-range-microvolt:
    description: Conversion range for ADC conversion 2.
    oneOf:
      - items:
          - enum: [-2500000, 0]
          - const: 2500000
      - items:
          - enum: [-12000000, 0]
          - const: 12000000
      - items:
          - const: -2500000
          - const: 0
```
 * `'#size-cells'` and `'#address-cells'` properties are only needed if your device node has children


### ABI
 * if adding a custom ABI file, make sure to specify the proper `KernelVersion:` when sending upstream

### Kconfig
 * select the buffer implementation needed for your driver, see below
 * select the bus-specific REGMAP config needed for your driver, see below
 * select GPIOLIB if needed for your driver, see below
```
config AD4130
	tristate "Analog Device AD4130 ADC Driver"
	depends on SPI
	select IIO_BUFFER
	select IIO_KFIFO_BUF
	select REGMAP_SPI
```


### Headers
 * sort them in alphabetical order
 * `#include <linux/module.h>` -> `#include <linux/mod_devicetable.h>`
 * replace usage of methods in `of.h` with methods in `property.h`
 * put asm includes after linux includes
 * separate subsystem includes (iio) from other linux includes
 * use definitions from `units.h` where applicable
 * do not define registers accessed implicitly


### Macros
 * have `()` around all usages of macro parameters
 * avoid multi-level macros
 * use `ARRAY_SIZE` where the size of an array is needed


### Registers
 * `FIELD_PREP` / `FIELD_GET`
 * `GENMASK` / `BIT`
 * pass driver state into `devm_regmap_init`
 * add _REG postfix for registers, add _MASK postfix for masks, put the name of the register it belongs to in the name of the mask, and, optionally, indent the masks by one space (looked ugly to me)
```
#define AD4130_ADC_CTRL_REG
#define  AD4130_ADC_CTRL_BIPOLAR_MASK
```


### Compatiblity
 * if the upstream version of a driver makes use of a new function or macro, you can maintain the same code downstream and add a compatibility section do your driver, eg:
```
/* 5.10 compatibility */
static int fwnode_irq_get_byname(struct fwnode_handle *fwnode, const char *name)
{
	int index;

	if (!name)
		return -EINVAL;

	index = fwnode_property_match_string(fwnode, "interrupt-names",  name);
	if (index < 0)
		return index;

	return fwnode_irq_get(fwnode, index);
}
static int iio_device_id(struct iio_dev *indio_dev)
{
	return indio_dev->id;
}

#include <linux/slab.h>
#define IIO_DMA_MINALIGN ARCH_KMALLOC_MINALIGN
/* end 5.10 compatibility */
```
 * if the upstream version of a driver makes use of a new function that cannot be provided by a simple compatibility function, describe the differences between upstream and our tree in a comment
```
	/* iio_device_id(indio_dev) -> indio_dev->id to compile against 5.10 */
	st->trig = devm_iio_trigger_alloc(st->dev, "%s-dev%d",
					  st->chip_info->name, indio_dev->id);
```


### Comments
 * `/* stuff */` comment format
 * add datasheet reference for comments extracted from the datasheet
```
	/*
	 * When the AVDD supply is set to below 2.5V the internal reference of
	 * 1.25V should be selected.
	 * See datasheet page 37, section ADC REFERENCE.
	 */
```
 * when using `regmap_write_bits()` as opposed to `regmap_update_bits()` because of hardware constraints (eg: one bit out of a register needs to be set to 1 even if it is already set to 1 to trigger a specific action) add a comment describing why
 * comment usage of `__aligned(IIO_DMA_MINALIGN)`
```
	/*
	 * DMA (thus cache coherency maintenance) requires the
	 * transfer buffers to live in their own cache lines.
	 */
```
 * also comment usage of mutex
```
	/*
	 * Synchronize access to members of the driver state, and ensure atomicity
	 * of consecutive regmap operations.
	 */
```


### Driver state
 * `put_unaligned_be`, `get_unaligned_be`
 * use `return dev_err_probe(dev, ret, "message")` to return errors out of probe functions 
 * use DMA-safe buffers for raw (and bulk) regmap reads


### IRQ
 * avoid having a required IRQ if possible, since board designers decide to not wire up IRQs when they are short on pins
 * do not force IRQ level (eg: `IRQF_TRIGGER_FALLING`) in `request_irq`, pass it from device tree
 * return IRQ_NONE in interrupt handlers if the interrupt didn’t actually do anything (ie: we were not waiting for one)
 * if the chip supports multiple IRQs but you only implement a single one in the driver (eg: ADC_RDY and ALERT), document this in the bindings, and use `fwnode_irq_get_byname()` to retrieve it, eg:
```
  interrupt-names:
    minItems: 1
    maxItems: 2
    items:
      enum:
        - adc_rdy
        - alert
```
```
	st->irq = fwnode_irq_get_byname(dev_fwnode(dev), "adc_rdy");

	if (st->irq == -EPROBE_DEFER)
		return -EPROBE_DEFER;


	if (st->irq < 0) {
		st->irq = 0;
		return 0;
	}
```


### IIO
 * use available_scan_masks, sort them numerically so that the iio core can demux them
 * for parts with FIFOs, make sure that the hwfifo_watermark attr takes the number of datum (scan elements as a whole) and not the number of individual scan elements
 * `iio_device_claim_direct_mode` before `mutex_lock` for driver mutex
 * do not set `*val2` when returning `IIO_VAL_INT`
 * do not store indio_dev into driver state, only go one way
 * do not use triggered buffer for devices that have a FIFO, as it cannot use any other trigger, use kfifo_buf
 * if using `devm_iio_triggered_buffer_setup()`, the top-half handler (third parameter) can be `NULL`, if, for example, you don't need the timestamp provided by `iio_pollfunc_store_time`
 * if your chip can also act as a GPIO controller, but some of the GPIOs can also be used for other functions (IRQs, for example), use the `valid_mask` functionality of the GPIO framework to disable the GPIOs, eg:
```
static int ad74115_gpio_init_valid_mask(struct gpio_chip *gc,
					unsigned long *valid_mask,
					unsigned int ngpios)
{
	struct ad74115_state *st = gpiochip_get_data(gc);

	*valid_mask = st->gpio_valid_mask;

	return 0;
}

...

	st->gpio_chip = (struct gpio_chip) {
		...
		.init_valid_mask = ad74115_gpio_init_valid_mask,
		...
	};

...
```

### Style
 * use `_MAX` suffix for enum members equal to the last possible member of an enum, see below
 * use `_NUM` suffix for enum members equal to the last possible member of an enum + 1, see below
 * no comma after last element of an enum, if that element is a `_NUM`, eg:
```
enum ad74115_adc_range {
	AD74115_ADC_RANGE_12V,
	AD74115_ADC_RANGE_12V_BIPOLAR,
	AD74115_ADC_RANGE_2_5V_BIPOLAR,
	AD74115_ADC_RANGE_2_5V_NEG,
	AD74115_ADC_RANGE_2_5V,
	AD74115_ADC_RANGE_0_625V,
	AD74115_ADC_RANGE_104MV_BIPOLAR,
	AD74115_ADC_RANGE_12V_OTHER,
	AD74115_ADC_RANGE_MAX = AD74115_ADC_RANGE_12V_OTHER,
	AD74115_ADC_RANGE_NUM
};
```
 * no comma after array terminating elements, eg:
```
static const struct spi_device_id ad74115_spi_id[] = {
	{ "ad74115h" },
	{ }
};
```
 * try to prefix driver methods that might (in the future) collide with methods defined in headers with part’s name
 * prefer returning errors early rather than indenting the success path
 * line length under 80 where possible, max 100
 * do not break up error message strings to preserve max line length
 * use `default` case for switch statements to error out of a function
 * use wildcard in MAINTAINERS file when matching multiple files of the same driver, eg:
```
ADXL367 THREE-AXIS DIGITAL ACCELEROMETER DRIVER
M:  Cosmin Tanislav <cosmin.tanislav@analog.com>
L:  linux-iio@vger.kernel.org
S:  Supported
W:  http://ez.analog.com/community/linux-device-drivers
F:  Documentation/devicetree/bindings/iio/accel/adi,adxl367.yaml
F:  drivers/iio/accel/adxl367*
```
 * use enum order for the cases of a switch where the value is an enum
 * structure copy based initialization can be used when assigning to a struct, eg:
```
st->gpio_chip = (struct gpio_chip) {
	.owner = ...,
	.label = ...,
        ...
};
```

### Other
 * EXPORT_SYMBOL_GPL_NS for symbols that are exported only locally for bus-specific parts of a driver to use, prefix the namespace name with IIO_ for iio subsystem
 * `fsleep()` can replace all other sleeping functions
