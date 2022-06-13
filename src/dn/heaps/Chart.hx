package dn.heaps;

import dn.Col;

class Chart extends dn.Process {
	public static var DEFAULT_SAMPLE_COUNT = 100;

	public var wid(default,set) : Int;
	public var hei(default,set) : Int;
	public var color(default,set) : Col;
	var dynMax = 0.;
	var avg = -1.;

	/** Shows an horizontal line at this value **/
	public var refValue(default,set) : Float = 0;

	public var maxValue(default,set) : Float = 0;

	/** Precision of the displayed number **/
	public var precision = 1;

	var pixels : h2d.SpriteBatch;
	var pixelPool : haxe.ds.Vector<h2d.SpriteBatch.BatchElement>;
	var chartInvalidated = true;
	var baseInvalidated = true;
	var showTexts = true;

	var freqS = 0.5;
	var autoPlotter : Null<Void->Float>;

	var history : haxe.ds.Vector<Float>;
	var curHistIdx = 0;
	var label : String;
	var lastTf : h2d.Text;
	var font : h2d.Font;
	var refLine : h2d.Bitmap;

	public function new(label="", color:Col=ColdLightGray, ?font:h2d.Font, p:Process) {
		super(p);

		this.color = color;
		this.font = font!=null ? font : hxd.res.DefaultFont.get();
		this.label = label;
		createRootInLayers(p.root, 99999);
		wid = 150;
		hei = 32;
		setMaxSamples(DEFAULT_SAMPLE_COUNT);
	}

	public function disableTexts() {
		showTexts = false;
		initBase();
	}

	/** Define the max number of values that will be displayed horizontally on the chart **/
	public function setMaxSamples(n:Int) {
		history = new haxe.ds.Vector(n);
		pixelPool = new haxe.ds.Vector(n);
		initBase();
	}

	public inline function setScale(v) {
		root.setScale(v);
	}

	public inline function setPosition(x,y) {
		root.setPosition(x,y);
	}

	inline function set_color(c) {
		color = c;
		chartInvalidated = true;
		return c;
	}

	inline function set_refValue(v) {
		refValue = v;
		chartInvalidated = true;
		return v;
	}

	inline function set_maxValue(v) {
		maxValue = v;
		chartInvalidated = true;
		return v;
	}

	inline function set_wid(v) {
		wid = v;
		baseInvalidated = true;
		return v;
	}

	inline function set_hei(v) {
		hei = v;
		baseInvalidated = true;
		return v;
	}

	override function onDispose() {
		super.onDispose();
		pixels = null;
		pixelPool = null;
		history = null;
	}

	function initBase() {
		root.removeChildren();

		var bg = new h2d.Graphics(root);
		bg.beginFill(color.toBlack(0.8));
		bg.lineStyle(1,color.toWhite(0.5));
		bg.drawRect(0,0,wid,hei);

		// Init pixels
		var t = h2d.Tile.fromColor(color);
		pixels = new h2d.SpriteBatch(t, root);
		pixels.hasRotationScale = true;
		var be = null;
		for(i in 0...pixelPool.length) {
			be = new h2d.SpriteBatch.BatchElement(t);
			pixels.add(be);
			be.visible = false;
			pixelPool[i] = be;
		}

		refLine = new h2d.Bitmap(root);

		if( showTexts ) {
			var labelTf = new h2d.Text(font, root);
			labelTf.text = label;
			labelTf.textColor = White;
			labelTf.x = 4;
			labelTf.y = hei-labelTf.textHeight-1;

			lastTf = new h2d.Text(font, root);
			lastTf.x = labelTf.x + labelTf.textWidth + 4;
			lastTf.textColor = color.toWhite(0.85);
			if( curHistIdx>0 )
				printLast(history[curHistIdx-1]);
		}
	}

	inline function printLast(v:Float) {
		if( showTexts ) {
			lastTf.text = Std.string( M.unit(v,precision) );
			lastTf.y = hei-lastTf.textHeight-1;
		}
	}

	function renderFullChart() {
		pixels.tile = h2d.Tile.fromColor(color);

		// Render chart
		var prev = null;
		var cur = null;
		var zero = getY(0);
		for(i in 0...curHistIdx) {
			cur = pixelPool[i];
			cur.x = getX(i);
			cur.y = getY(history[i]);
			cur.scaleY = zero-cur.y;
			cur.visible = true;
		}

		// Clear remaining
		for(i in curHistIdx...pixelPool.length)
			pixelPool[i].visible = false;

		// Reference value line
		refLine.visible = refValue!=0;
		if( refLine.visible ) {
			refLine.tile = h2d.Tile.fromColor( color.toWhite(0.7), 1,1, 0.5 );
			refLine.scaleX = wid;
			refLine.y = getY(refValue);
		}
	}

	public function plot(v:Float) {
		updateMax(v);

		history[curHistIdx] = v;

		// Render
		var be = pixelPool[curHistIdx];
		be.visible = true;
		be.x = getX(curHistIdx);
		be.y = getY(v);
		be.scaleY = getY(0)-be.y;

		printLast(v);
		curHistIdx++;

		// Scroll back
		if( curHistIdx>=history.length ) {
			dynMax = 0;
			avg = -1;
			var chunk = Std.int( history.length*0.33 );
			for(i in chunk...history.length) {
				history[i-chunk] = history[i];
				updateMax( history[i] );
			}

			curHistIdx-=chunk;

			chartInvalidated = true;
		}
	}

	inline function updateMax(v:Float) {
		if( maxValue!=0 ) {
			// Fixed custom max
			dynMax = maxValue;
		}
		else {
			// Dynamic max
			if( avg==-1 )
				avg = v;
			else
				avg = avg*0.7 + v*0.3;

			if( avg>dynMax || dynMax>avg*5 ) {
				dynMax = avg*3;
				chartInvalidated = true;
			}
		}
	}

	public function autoPlot( valueGetter:Void->Float, freqS:Float ) {
		this.freqS = freqS;
		autoPlotter = valueGetter;
	}

	inline function getX(idx:Int) return M.round( idx/history.length * wid );
	inline function getY(v:Float) return M.imax(0, M.round( hei - v/dynMax*hei ));

	override function update() {
		super.update();

		if( autoPlotter!=null ) {
			if( !cd.hasSetS("autoPlot",freqS) )
				plot( try autoPlotter() catch(_) 0 );
		}
	}

	override function postUpdate() {
		super.postUpdate();

		if( baseInvalidated) {
			initBase();
			chartInvalidated = true;
			baseInvalidated = false;
		}

		if( chartInvalidated ) {
			renderFullChart();
			chartInvalidated = false;
		}
	}
}